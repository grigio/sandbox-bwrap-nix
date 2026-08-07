#!/bin/sh
set -euo pipefail

command -v bwrap >/dev/null 2>&1 || { echo "bwrap not found"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NIX_BIN_REAL=$(readlink -f "$(command -v nix)") || { echo "nix not found"; exit 1; }

SANDBOX_PASSWD=$(mktemp /tmp/sandbox-passwd-XXXXXX)
SANDBOX_GROUP=$(mktemp /tmp/sandbox-group-XXXXXX)
cleanup() { rm -f "$SANDBOX_PASSWD" "$SANDBOX_GROUP"; }
trap cleanup EXIT

HOST_USER=$(whoami)
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# X11 authentication token. --clearenv strips XAUTHORITY, so GUI apps (e.g. the
# browser tool's Firefox) opening the shared display would be rejected on hosts
# whose X server uses auth. Pass it through only when an authority file exists.
XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"
[ -f "$XAUTH" ] && XAUTH_PRESENT=1 || XAUTH_PRESENT=0

grep -v "^${HOST_USER}:" /etc/passwd > "$SANDBOX_PASSWD"
echo "nixuser:x:${HOST_UID}:${HOST_GID}:sandbox user:${SCRIPT_DIR}/sandbox-home:/bin/bash" >> "$SANDBOX_PASSWD"
grep -v "^${HOST_USER}:" /etc/group > "$SANDBOX_GROUP"
echo "nixuser:x:${HOST_GID}:" >> "$SANDBOX_GROUP"

# On NixOS /bin/bash may not exist; find bash via /bin/sh or PATH
BASH_PATH=/bin/bash
[ ! -f "$BASH_PATH" ] && command -v bash >/dev/null 2>&1 && BASH_PATH=$(readlink -f "$(command -v bash)")
[ ! -f "$BASH_PATH" ] && [ -f /bin/sh ] && BASH_PATH=$(readlink -f /bin/sh)

# On NixOS /etc/ssl/certs/ca-certificates.crt is a symlink chain into /nix/store
SSL_CERT=$(readlink -f /etc/ssl/certs/ca-certificates.crt 2>/dev/null || echo "/etc/ssl/certs/ca-certificates.crt")

# Let bwrap build /dev itself (--dev): it mounts a fresh tmpfs, binds the
# essential device nodes, mounts a private devpts instance, and points
# /dev/ptmx at it. Doing the devpts mount as a manual `mount` *inside* the
# sandbox fails on CI: bwrap runs unprivileged there and uses a user namespace
# where the process is not root (no CAP_SYS_ADMIN), so the mount dies with
# "must be superuser to use mount". bwrap performs --dev setup while it still
# holds CAP_SYS_ADMIN inside the user namespace, so it works unprivileged.
#
# /dev/ptmx must point at the private devpts (pts/ptmx): the kernel's
# path_connected() check treats a plain bind of /dev/ptmx as disconnected from
# its parent dir, so ptmx_open() fails to find the devpts instance (ENOENT) and
# nix develop dies with "opening pseudoterminal master: No such file or
# directory". nix allocates its pty before the shellHook runs, so this cannot
# live in the flake shellHook; the wrapper below runs nix under script(1).
#
# NOTE on browsers: the sandbox is not self-contained for the browser tool. The
# flake deliberately does NOT ship a nixpkgs Firefox (nixpkgs-unstable ~153 is
# currently incompatible with the jcode browser bridge; host Firefox ~136
# works), so the browser tool relies on a host browser landed in the chroot from
# the read-only /usr/bin bind below. Keep that bind, or the tool cannot connect.
bwrap \
  --clearenv \
  --share-net \
  --unshare-pid \
  --die-with-parent \
  --unshare-uts \
  --bind /nix/store /nix/store \
  --bind /nix/var/nix /nix/var/nix \
  --tmpfs /nix/var/nix/builds \
  --ro-bind /bin/sh /bin/sh \
  --ro-bind "$BASH_PATH" /bin/bash \
  --ro-bind "$NIX_BIN_REAL" /usr/bin/nix \
  $( [ -d /usr/bin ] && echo "--ro-bind /usr/bin /usr/bin" ) \
  $( [ -d /usr/lib ] && echo "--ro-bind /usr/lib /usr/lib" ) \
  $( [ -d /usr/lib64 ] && echo "--ro-bind /usr/lib64 /usr/lib64 --symlink /usr/lib64 /lib64" ) \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/hosts /etc/hosts \
  --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf \
  --ro-bind "$SANDBOX_PASSWD" /etc/passwd \
  --ro-bind "$SANDBOX_GROUP" /etc/group \
  $( [ -d /usr/share ] && echo "--ro-bind-try /usr/share /usr/share" || true ) \
  --ro-bind-try /etc/fonts /etc/fonts \
  --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
  --ro-bind-try /etc/gtk-3.0 /etc/gtk-3.0 \
  --ro-bind-try /etc/alternatives /etc/alternatives \
  --ro-bind "$SSL_CERT" /etc/ssl/certs/ca-certificates.crt \
  --bind "$PWD" "$PWD" \
  --bind "$SCRIPT_DIR" "$SCRIPT_DIR" \
  --bind "$SCRIPT_DIR/sandbox-home" "$SCRIPT_DIR/sandbox-home" \
  $( [ -d "$HOME/.config/opencode/skills" ] && echo "--bind $HOME/.config/opencode/skills $SCRIPT_DIR/sandbox-home/.config/opencode/skills" || echo "--tmpfs $SCRIPT_DIR/sandbox-home/.config/opencode/skills" ) \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --tmpfs /dev/shm \
  --ro-bind-try /sys /sys \
  --ro-bind-try /etc/machine-id /etc/machine-id \
  --ro-bind-try /var/lib/dbus/machine-id /var/lib/dbus/machine-id \
  --ro-bind-try /run/dbus/system_bus_socket /run/dbus/system_bus_socket \
  $( [ -d /dev/dri ] && echo "--dev-bind /dev/dri /dev/dri" ) \
  $( [ -n "${DISPLAY:-}" ] && echo "--ro-bind-try /tmp/.X11-unix /tmp/.X11-unix --setenv DISPLAY ${DISPLAY}" ) \
  $( [ "$XAUTH_PRESENT" = 1 ] && echo "--ro-bind-try $XAUTH $XAUTH --setenv XAUTHORITY $XAUTH" ) \
  $( [ -n "${XDG_RUNTIME_DIR:-}" ] && echo "--bind ${XDG_RUNTIME_DIR} ${XDG_RUNTIME_DIR} --setenv XDG_RUNTIME_DIR ${XDG_RUNTIME_DIR}" ) \
  $( [ -n "${WAYLAND_DISPLAY:-}" ] && echo "--setenv WAYLAND_DISPLAY ${WAYLAND_DISPLAY}" ) \
  \
  --ro-bind-try /etc/localtime /etc/localtime \
  --ro-bind-try /etc/hostname /etc/hostname \
  \
  --setenv HOME "$SCRIPT_DIR/sandbox-home" \
  --setenv PATH "/bin:/usr/bin" \
  --setenv TMPDIR /tmp \
  --setenv TERM "${TERM:-xterm-256color}" \
  --chdir "$PWD" \
  /bin/bash -c '
    set -e
    # Run nix under script(1) so the dev shell gets a pty from the private
    # devpts that bwrap mounted at /dev/pts (--dev). Otherwise nix allocates
    # one itself, and the outer terminal, which belongs to the host devpts
    # instance, would not resolve via ttyname().
    cmd=$(printf "%q " "$@")
    exec script -qec "$cmd" /dev/null
  ' _ "$NIX_BIN_REAL" --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$SCRIPT_DIR" -c "${@:-bash}"
