#!/usr/bin/env bash
# Regenerate the version badge JSONs under badges/ from the versions pinned in
# the current flake.lock.
#
# Used by:
#   - .github/workflows/update-flake.yml  (daily flake.lock update, committed
#     together with the lock so the badge never lags behind)
#   - .github/workflows/versions.yml      (daily + on push, catches version
#     changes that arrive without a flake.lock update)
#
# Also runnable locally, e.g. `nix develop --command bash scripts/update-badges.sh`
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p badges

# The versions below are the actual binaries the dev shell would provide.
# jcode comes from the `jcode` flake input (github:grigio/jcode), which is
# bumped by `nix flake update` just like nixpkgs.
opencode_version="$(nix shell --inputs-from . 'nixpkgs#opencode' -c opencode --version | tail -n 1)"
jcode_version="$(nix shell --inputs-from . 'jcode#default' -c jcode --version | tail -n 1 | sed -E 's/.*v([0-9]+(\.[0-9]+)*).*/\1/')"
pi_version="$(nix shell --inputs-from . 'nixpkgs#pi-coding-agent' -c pi --version | tail -n 1)"
# dsh (deepseek-harness) --version prints "0.1.0-rc.6"
dsh_version="$(nix shell --inputs-from . '.#deepseek-harness' -c dsh --version | tail -n 1 | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?).*/\1/')"

test -n "$opencode_version"
test -n "$jcode_version"
test -n "$pi_version"
test -n "$dsh_version"

cat > badges/opencode.json <<EOF
{
  "schemaVersion": 1,
  "label": "opencode",
  "message": "$opencode_version",
  "color": "blue"
}
EOF

cat > badges/jcode.json <<EOF
{
  "schemaVersion": 1,
  "label": "jcode",
  "message": "$jcode_version",
  "color": "green"
}
EOF

cat > badges/pi-coding-agent.json <<EOF
{
  "schemaVersion": 1,
  "label": "pi-coding-agent",
  "message": "$pi_version",
  "color": "purple"
}
EOF


cat > badges/deepseek-harness.json <<EOF
{
  "schemaVersion": 1,
  "label": "deepseek-harness",
  "message": "$dsh_version",
  "color": "red"
}
EOF

echo "badges: opencode=$opencode_version jcode=$jcode_version pi-coding-agent=$pi_version deepseek-harness=$dsh_version"
