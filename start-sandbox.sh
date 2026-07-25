#!/bin/sh

command -v bwrap >/dev/null 2>&1 || { echo "bwrap not found"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NIX_BIN=$(command -v nix) || { echo "nix not found"; exit 1; }
NIX_BIN_REAL=$(readlink -f "$NIX_BIN")

bwrap \
  --clearenv \
  --share-net \
  --unshare-pid \
  --bind /nix/store /nix/store \
  --bind /nix/var/nix /nix/var/nix \
  --tmpfs /nix/var/nix/builds \
  --ro-bind /bin/sh /bin/sh \
  --ro-bind /bin/bash /bin/bash \
  $(case "$NIX_BIN" in /nix/store/*|/nix/var/nix/*) ;; *) echo "--ro-bind $NIX_BIN $NIX_BIN" ;; esac) \
  --bind /usr/lib /usr/lib \
  $( [ -d /usr/lib64 ] && echo "--bind /usr/lib64 /usr/lib64 --symlink /usr/lib64 /lib64" ) \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/hosts /etc/hosts \
  --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/group /etc/group \
  --ro-bind /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt \
  --bind "$PWD" "$PWD" \
  --bind "$SCRIPT_DIR" "$SCRIPT_DIR" \
  --bind "$SCRIPT_DIR/sandbox-home" "$SCRIPT_DIR/sandbox-home" \
  $( [ -d "$HOME/.config/opencode/skills" ] && echo "--bind $HOME/.config/opencode/skills $SCRIPT_DIR/sandbox-home/.config/opencode/skills" || echo "--tmpfs $SCRIPT_DIR/sandbox-home/.config/opencode/skills" ) \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --setenv HOME "$SCRIPT_DIR/sandbox-home" \
  --setenv PATH "/bin:/usr/bin" \
  --setenv TMPDIR /tmp \
  --setenv TERM "$TERM" \
  --chdir "$PWD" \
  "$NIX_BIN_REAL" --extra-experimental-features "nix-command flakes" develop "$SCRIPT_DIR" -c "${@:-bash}"
