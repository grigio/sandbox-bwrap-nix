#!/usr/bin/env bash
# Bump the maki pin in flake.nix to the latest GitHub release.
#
# Maki (https://github.com/tontinton/maki) is an AI coding agent that ships
# prebuilt per-platform tarballs on GitHub Releases under a single vX.Y.Z tag
# track. This flake uses the x86-64 musl build:
#     maki-vX.Y.Z-x86_64-unknown-linux-musl.tar.gz
#
# The sha256 comes from the release's own sha256sums.txt asset (no tarball
# download); `nix build .#maki` then verifies it end to end (a wrong hash
# or URL makes the fixed-output fetch fail, so no bad pins ever get committed).
#
# Requirements: curl, jq, sed, nix (all present in this repo's dev shell and
# on the GitHub runners). Run locally:
#     bash scripts/update-maki.sh
# Used automatically by .github/workflows/update-maki.yml.
#
# Prints "changed=true|false" (and appends to $GITHUB_OUTPUT when set) so
# callers know whether to commit.
set -euo pipefail

cd "$(dirname "$0")/.."

repo="tontinton/maki"
# The asset name embeds the version, so it's derived from the tag below.
asset_for() {
  printf 'maki-v%s-x86_64-unknown-linux-musl.tar.gz' "$1"
}

# --- exit helper that also reports the change status -----------------------
finish() {
  changed="$1"
  shift
  printf '%s\n' "$*" >&2
  echo "changed=$changed"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "changed=$changed" >> "$GITHUB_OUTPUT"
  fi
  exit 0
}

# --- latest release tag (single vX.Y.Z track, API returns newest first) ----
latest_tag="$(
  curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=100" \
    | jq -r '.[].tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' \
    | head -n 1
)"
test -n "$latest_tag" || { echo "error: no maki release tag found" >&2; exit 1; }

# --- currently pinned version in flake.nix -----------------------------------
pinned="$(
  sed -nE '/^[[:space:]]*makiFor = system:/,/^[[:space:]]*};$/ {
    s/^[[:space:]]*version = "([0-9]+\.[0-9]+\.[0-9]+)";/\1/p
  }' flake.nix | tail -n 1
)"
test -n "$pinned" || { echo "error: could not read pinned maki version from flake.nix" >&2; exit 1; }

new_version="${latest_tag#v}"
if [ "$new_version" = "$pinned" ]; then
  finish false "maki: already on the latest release v${pinned}, nothing to do"
fi

# never downgrade (e.g. a manually pinned newer version, or API ordering oddity)
newest="$(printf '%s\n%s\n' "$pinned" "$new_version" | sort -V | tail -n 1)"
if [ "$newest" != "$new_version" ]; then
  finish false "maki: pinned v${pinned} is newer than latest release v${new_version}, skipping"
fi

echo "maki: bumping v${pinned} -> v${new_version}"

asset="$(asset_for "$new_version")"

# --- sha256 of the linux tarball from the release's sha256sums.txt asset -----
hex="$(
  curl -fsSL "https://github.com/${repo}/releases/download/${latest_tag}/sha256sums.txt" \
    | awk -v a="$asset" '$2 == a { print $1 }'
)"
test -n "$hex" || { echo "error: ${asset} missing from sha256sums.txt of ${latest_tag}" >&2; exit 1; }

# hex -> SRI ("sha256-<base64>"); nix hash convert is the modern spelling,
# to-sri the older one, python3 as a last resort.
sri=""
if command -v nix >/dev/null 2>&1; then
  sri="$(nix hash convert --hash-algo sha256 --to sri "$hex" 2>/dev/null | tail -n 1 || true)"
  if [ -z "$sri" ]; then
    sri="$(nix hash to-sri --type sha256 "$hex" 2>/dev/null | tail -n 1 || true)"
  fi
fi
if [ -z "$sri" ] && command -v python3 >/dev/null 2>&1; then
  sri="$(python3 -c 'import base64,sys; print("sha256-"+base64.b64encode(bytes.fromhex(sys.argv[1])).decode().rstrip("="))' "$hex" || true)"
fi
test -n "$sri" || { echo "error: could not convert sha256 ${hex} to SRI format" >&2; exit 1; }

# --- rewrite the two pins, only inside the makiFor block ----------------------
# flake.nix also pins reasonix with its own version/hash, so the substitutions
# are scoped with a sed range from the `makiFor = system:` line to the first
# `};` line (both the version and hash lines precede that closing brace).
sed -i -E "/^[[:space:]]*makiFor = system:/,/^[[:space:]]*};$/ {
  s/version = \"[0-9]+\.[0-9]+\.[0-9]+\";/version = \"${new_version}\";/
  s|hash = \"sha256-[A-Za-z0-9+/=]+\";|hash = \"${sri}\";|
}" flake.nix
git diff --stat flake.nix

# --- verify the pin actually fetches and builds -------------------------------
echo "maki: validating with 'nix build .#maki' ..."
nix build .#maki

finish true "maki: updated to v${new_version} (${sri})"
