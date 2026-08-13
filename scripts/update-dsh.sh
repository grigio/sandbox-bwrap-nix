#!/usr/bin/env bash
# Bump the deepseek-harness (dsh) pin in flake.nix to the latest @deepseek-ai/dsh
# npm release.
#
# DeepSeek Harness (https://github.com/deepseek-ai/deepseek-harness) distributes
# the `dsh` CLI as the public npm package @deepseek-ai/dsh (there are no GitHub
# releases or prebuilt nix binaries). This flake wraps the published tarball
# with nixpkgs' buildNpmPackage:
#
#   - vendor/dsh/package-lock.json  the lock generated from the tarball at the
#                                   pinned version (the published tarball ships
#                                   no lockfile, but npm ci needs one)
#   - flake.nix version/hash pins    the deepseekHarnessFor block: `version`,
#                                   the tarball src hash and the npmDepsHash
#
# On bump this script re-downloads the tarball, regenerates the vendored lock
# from the new version, computes the new npmDepsHash (via prefetch-npm-deps,
# the same tool the nixpkgs fetcher uses), rewrites the pins, and validates
# with `nix build .#deepseek-harness` so a wrong URL/hash/lock never commits.
#
# Requirements: curl, jq, node, npm, sha256sum, nix (all present in this repo's
# dev shell and on the GitHub runners). Run locally:
#     bash scripts/update-dsh.sh
# Used automatically by .github/workflows/update-dsh.yml.
#
# Prints "changed=true|false" (and appends to $GITHUB_OUTPUT when set) so
# callers know whether to commit.
set -euo pipefail

cd "$(dirname "$0")/.."

pkg="@deepseek-ai/dsh"
npm_url="https://registry.npmjs.org/${pkg}"

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

command -v node >/dev/null 2>&1 || { echo "error: node is required (regenerates the vendored package-lock)" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "error: npm is required (regenerates the vendored package-lock)" >&2; exit 1; }

# --- latest published version from the npm registry (dist-tags.latest) ------
latest_version="$(
  curl -fsSL "${npm_url}" | jq -r '.["dist-tags"].latest'
)"
test -n "$latest_version" || { echo "error: could not resolve ${pkg} latest version" >&2; exit 1; }

# --- currently pinned version in flake.nix -----------------------------------
pinned="$(
  sed -nE '/^[[:space:]]*deepseekHarnessFor = system:/,/^[[:space:]]*};$/ {
    s/^[[:space:]]*version = "([^"]+)";/\1/p
  }' flake.nix | tail -n 1
)"
test -n "$pinned" || { echo "error: could not read pinned dsh version from flake.nix" >&2; exit 1; }

if [ "$latest_version" = "$pinned" ]; then
  finish false "dsh: already on the latest release ${pinned}, nothing to do"
fi

echo "dsh: bumping ${pinned} -> ${latest_version}"

# --- set up a temp dir (download + lock generation; keep the repo clean until
# the rewrite step) ------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dsh-update-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

tarball="$WORK/dsh.tgz"
curl -fsSL "${npm_url}/-"/dsh-${latest_version}.tgz -o "$tarball"

# --- sha256 of the tarball (hex -> SRI) --------------------------------------
hex="$(sha256sum "$tarball" | awk '{print $1}')"
sri="$(nix hash convert --hash-algo sha256 --to sri "$hex" 2>/dev/null | tail -n 1 || true)"
if [ -z "$sri" ]; then
  sri="$(nix hash to-sri --type sha256 "$hex" 2>/dev/null | tail -n 1 || true)"
fi
test -n "$sri" || { echo "error: could not convert sha256 ${hex} to SRI format" >&2; exit 1; }

# --- regenerate the vendored lock from the new tarball ------------------------
# The published tarball ships no package-lock.json. Run npm inside the package
# dir so the resolved tree matches the tarball's package.json (including
# devDependencies that npm ci expects back).
mkdir -p "$WORK/pkg"
tar -xzf "$tarball" -C "$WORK/pkg"
PACKAGE_DIR="$WORK/pkg/package"
test -f "$PACKAGE_DIR/package.json" || { echo "error: ${pkg} tarball has no package/package.json" >&2; exit 1; }

(cd "$PACKAGE_DIR" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund)

test -f "$PACKAGE_DIR/package-lock.json" || { echo "error: could not generate package-lock.json for ${pkg} ${latest_version}" >&2; exit 1; }

# --- npmDepsHash for the new lock ---------------------------------------------
# prefetch-npm-deps computes the exact hash nixpkgs' fetchNpmDeps needs. It is
# not part of the sandbox's fixed package list, so resolve it from nixpkgs on
# demand (cache.nixos.org serves the prebuilt binary).
prefetch="$(nix build --no-link --print-out-paths nixpkgs#prefetch-npm-deps 2>/dev/null | tail -n 1)/bin/prefetch-npm-deps"
test -x "$prefetch" || { echo "error: could not build nixpkgs#prefetch-npm-deps" >&2; exit 1; }

npmdeps_hash="$("$prefetch" "$PACKAGE_DIR/package-lock.json")"
test -n "$npmdeps_hash" || { echo "error: could not derive npmDepsHash for ${pkg} ${latest_version}" >&2; exit 1; }

# --- rewrite the pins, only inside the deepseekHarnessFor block ---------------
# version, the tarball src hash, and the npmDepsHash all live in that block.
sed -i -E "/^[[:space:]]*deepseekHarnessFor = system:/,/^[[:space:]]*};$/ {
  s/version = \"[^\"]+\";/version = \"${latest_version}\";/
  s|hash = \"sha256-[A-Za-z0-9+/=]+\";|hash = \"${sri}\";|
  s|npmDepsHash = \"sha256-[A-Za-z0-9+/=]+\";|npmDepsHash = \"${npmdeps_hash}\";|
}" flake.nix

# --- replace the vendored lock -------------------------------------------------
cp "$PACKAGE_DIR/package-lock.json" vendor/dsh/package-lock.json

git diff --stat flake.nix vendor/dsh/package-lock.json

# --- verify the pin actually builds ---------------------------------------------
echo "dsh: validating with 'nix build .#deepseek-harness' ..."
nix build ".#deepseek-harness"

finish true "dsh: updated to ${latest_version} (${sri})"