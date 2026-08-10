# sandbox-bwrap-nix

[![Sandbox CI](https://github.com/grigio/sandbox-bwrap-nix/actions/workflows/sandbox.yml/badge.svg)](https://github.com/grigio/sandbox-bwrap-nix/actions/workflows/sandbox.yml)
[![opencode version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/grigio/sandbox-bwrap-nix/master/badges/opencode.json)](https://github.com/grigio/sandbox-bwrap-nix)
[![jcode version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/grigio/sandbox-bwrap-nix/master/badges/jcode.json)](https://github.com/grigio/sandbox-bwrap-nix)
[![pi-coding-agent version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/grigio/sandbox-bwrap-nix/master/badges/pi-coding-agent.json)](https://github.com/grigio/sandbox-bwrap-nix)
[![reasonix version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/grigio/sandbox-bwrap-nix/master/badges/reasonix.json)](https://github.com/grigio/sandbox-bwrap-nix)
[![maki version](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/grigio/sandbox-bwrap-nix/master/badges/maki.json)](https://github.com/grigio/sandbox-bwrap-nix)

Super simple, fast and effective sandbox to run commands in a lightweight bubblewrap + nix sandbox. No docker/podman containers needed

It's useful to run AI agent harness like `opencode` isolated from the main system and you can also install packages as normal user without mess the host system.

Isolates Nix operations from your host filesystem while preserving access to `/nix/store` and `/nix/var/nix`. Useful for safely experimenting with Nix builds, running [OpenCode](https://opencode.ai) in a sandbox, or containing AI coding tools.

## Quick start

```bash
./start-sandbox.sh
```

This drops you into a sandboxed bash shell with Nix, git, bun, uv, jcode, and other tools pre-installed. The sandbox-home directory acts as `$HOME`.

![sandbox-bwrap-nix demo](sandbox-bwrap-nix.gif)

## Installation

Add a persistent alias to your shell config (e.g. `~/.bashrc` or `~/.zshrc`):

```bash
alias sss=/path/to/sandbox-bwrap-nix/start-sandbox.sh
```

Replace `/path/to/sandbox-bwrap-nix` with the absolute path to this directory (use `pwd` to get it). After adding the line, reload with `source ~/.bashrc` (or open a new terminal), then launch with `sss`.

### Example usage

```
➜  demo git:(master) ✗ ls ../
-               examples      ggml.h            main           rec.wav
bench           extra         ggml-metal.h      Makefile       run.sh
bindings        ggml-alloc.c  ggml-metal.m      models         samples
build           ggml-alloc.h  ggml-metal.metal  openvino       stream
cmake           ggml-alloc.o  ggml.o            quantize       tests
CMakeLists.txt  ggml.c        ggml-opencl.cpp   README.md      whisper.cpp
coreml          ggml-cuda.cu  ggml-opencl.h     rec16.wav      whisper.h
demo            ggml-cuda.h   LICENSE           rec16.wav.wts  whisper.o
➜  demo git:(master) ✗ sss ls ../
=== sandbox-bwrap-nix development shell ===
  nixpkgs: nixpkgs-unstable (20260809 - 7525d99)
  XKB_CONFIG_ROOT=/nix/store/xxx-xkeyboard-config/share/X11/xkb
demo
➜  demo git:(master) ✗ opencode --version
1.18.4
➜  demo git:(master) ✗ sss opencode --version
=== sandbox-bwrap-nix development shell ===
  nixpkgs: nixpkgs-unstable (20260809 - 7525d99)
  XKB_CONFIG_ROOT=/nix/store/xxx-xkeyboard-config/share/X11/xkb
1.18.3
➜  demo git:(master) ✗ sss
=== sandbox-bwrap-nix development shell ===
  nixpkgs: nixpkgs-unstable (20260809 - 7525d99)
  XKB_CONFIG_ROOT=/nix/store/xxx-xkeyboard-config/share/X11/xkb
● demo $ ls ../
demo
```

## How it works

[`start-sandbox.sh`](start-sandbox.sh) invokes `bwrap` with:

| Mount | Type | Purpose |
|-------|------|---------|
| `/nix/store`, `/nix/var/nix` | bind (rw) | Nix store access (shared with the host) |
| `/nix/var/nix/builds` | tmpfs | Isolate builds |
| `/bin/sh`, `/bin/bash`, `/usr/bin/nix` | bind (ro) | Essential binaries |
| `/usr/lib`, `/usr/lib64` | bind (ro) | Shared libraries |
| `/etc/resolv.conf`, `/etc/hosts`, `/etc/nsswitch.conf` | bind (ro) | DNS / name resolution |
| SSL certs | bind (ro) | HTTPS support |
| `sandbox-home/` | bind | Isolated home dir |
| `/tmp` | tmpfs | Temporary files |
| `/proc` | procfs | Process access |
| `/dev` | tmpfs + device binds + fresh devpts | Only `null/zero/full/random/urandom/tty` bound from host; pty support via a fresh devpts instance mounted inside (`/dev/ptmx` → `pts/ptmx`) |

The environment is cleared (`--clearenv`), networking is shared (`--share-net`), and PID namespace is unshared (`--unshare-pid`).

Inside the sandbox, `nix develop` with the [flake](flake.nix) provisions a dev shell containing: **nix, git, bun, uv, jcode, opencode, pi-coding-agent, reasonix, maki, codex, cargo, yt-dlp, gnumake, micro, less, btop**, bash completion, and the `clear`/`reset` terminal commands (ncurses).

## What the sandbox isolates (and what it doesn't)

The sandbox is a blast-radius reduction for convenient everyday use, not a hard security boundary. It keeps AI agents and experiments away from your host filesystem, processes, and home, while deliberately sharing the things needed to be useful: the network, the nix store, and the current directory.

### Isolated

| Area | Mechanism | Effect |
|-------|-----------|--------|
| Filesystem | Mount namespace with explicit binds | Only the paths in the table above are visible. `$HOME`, `/etc`, `/root`, host mounts: all invisible |
| Writable surface | rw binds limited to `$PWD`, the repo dir, `sandbox-home/`, `/nix/var/nix` | Outside the explicitly bound paths there is nothing to delete or modify |
| Home directory | `--setenv HOME "$SCRIPT_DIR/sandbox-home"` | The real `$HOME` is not bound; the sandbox gets its own home |
| Environment | `--clearenv` | No host variables leak; only `HOME`, `PATH`, `TMPDIR`, `TERM` are set |
| Processes | `--unshare-pid` + fresh `/proc` | Host processes are invisible; they can't be inspected or signalled |
| Hostname | `--unshare-uts` | Private hostname namespace |
| `/tmp`, `/dev/shm` | tmpfs | Private scratch space |
| `/dev` | tmpfs dev setup via `--dev` | Only `null/zero/full/random/urandom/tty` bound from host plus a private devpts instance (`/dev/ptmx` → `pts/ptmx`). No block devices, no host ptys |
| Users | Synthetic `/etc/passwd`, `/etc/group` | Only the current user exists (as `nixuser`); host accounts are absent |
| Nix build dirs | `/nix/var/nix/builds` tmpfs | Build artifacts in that path never touch the host |

### Not isolated (by design)

| Area | Mechanism | Consequence |
|-------|-----------|-------------|
| Network | `--share-net` | Same host IP; LAN, internet, and localhost are all reachable. No egress restrictions |
| User identity | Same uid/gid as the host user | Files in shared paths are owned by you; host permission checks apply |
| Nix store | `/nix/store` and `/nix/var/nix` bound read-write | The store is the host store. Tools can read and (where permissions allow) write it; a hostile process could poison store paths |
| Nix daemon | Socket at `/nix/var/nix/daemon-socket` | `nix build` through the daemon executes on the host, outside the sandbox |
| Current directory | `--bind "$PWD" "$PWD"` | Everything in the directory you launched from is shared both ways |
| `sandbox-home/` | Real directory on the host | Files persist and are visible from the host |
| OpenCode skills | `~/.config/opencode/skills` bound in | When present on the host, the sandbox reads and writes them |
| Kernel & capabilities | Shared kernel; `bwrap` runs unprivileged in a user namespace | `--dev` setup (incl. the private devpts mount) is done by bwrap itself while it holds CAP_SYS_ADMIN inside the user namespace, so it works without setuid/setcap bwrap; it cannot touch host sysctls or devices |

**Bottom line:** this is containment for everyday use — run AI agents here so they can't read your SSH keys or delete files outside the shared paths — not a sandbox for running untrusted or adversarial code. Anything inside it has network access and reach into the nix store.

## Why bwrap instead of plain `nix develop`

| Aspect | `nix develop` alone | `bwrap` + `nix develop` |
|--------|-------------------|------------------------|
| **Filesystem** | Full host access | Only explicitly bound paths visible |
| **Environment** | Inherits all host vars | `--clearenv` gives a clean slate |
| **Process isolation** | Shares host PID namespace | `--unshare-pid` hides host processes |
| **Home directory** | Real `$HOME` | Isolated `sandbox-home/` |
| **Security** | AI tools can read/write any file | Accidental `rm -rf` stays contained |
| **Reproducibility** | Host state leaks in | Minimal, controlled surface |

bwrap is also lighter than containers — no daemon, no image pulls, no layers, no `sudo`. Just namespaces and bind mounts.

## jcode: prebuilt binary, no compilation

[jcode](https://github.com/1jehuang/jcode) is provided as a prebuilt binary from the
[grigio Nix binary cache](https://grigio.github.io/jcode)
(install docs: <https://github.com/grigio/jcode#install-flake>). It is never compiled in
this repo: the cache publishes both the `jcode` binary and its crane `cargoArtifacts`
dependency layer, so `nix develop` only downloads the closure.

The cache is configured in two places:

- `nixConfig` in [`flake.nix`](flake.nix) — applies to every `nix develop`, `nix build`
  and `nix flake check` run in this repo
- `sandbox-home/.config/nix/nix.conf` — the Nix config inside the sandbox (Nix runs with
  `HOME=sandbox-home`, so it reads this file)

Paths the cache does not have fall back to building from source. The grigio
cache only publishes **x86_64-linux**, so on that platform jcode is a pure
download. This flake targets x86_64-linux only: reasonix is published for
x86-64 (amd64) and CI runs on x86_64 runners.

## Requirements

- Linux with [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`) installed
- Nix with flakes and `nix-command` enabled on the host

## Project structure

```
├── start-sandbox.sh        # Entry point — invokes bwrap
├── flake.nix               # Nix flake with dev shell definition
├── flake.lock              # Pinned nixpkgs revision
├── badges/                 # Version badge data (opencode, jcode, pi-coding-agent, reasonix, maki), updated by CI
├── scripts/
│   ├── update-badges.sh      # Regenerates badges/ from the versions pinned in the flake (used by CI, runnable locally)
│   ├── update-reasonix.sh    # Bumps the reasonix version/hash pins in flake.nix to the latest GitHub CLI release (used by CI, runnable locally)
│   └── update-maki.sh        # Bumps the maki version/hash pins in flake.nix to the latest GitHub release (used by CI, runnable locally)
├── .github/workflows/      # GitHub Actions: sandbox CI, flake.lock updater, reasonix/maki pin updaters, version badge updater
├── sandbox-home/           # Isolated home directory
│   ├── .bashrc             # Colored prompt, git branch, aliases
│   ├── .bash_profile       # Sources .bashrc
│   ├── SANDBOX             # Marker file (empty)
│   └── .config/
│       ├── nix/nix.conf    # Enables flakes + nix-command + jcode binary cache
│       └── opencode/       # OpenCode config (skills, AGENTS.md)
├── .gitignore              # Ignores generated runtime artifacts
├── LICENSE                 # MIT License
└── README.md
```

## sandbox-home

A minimal home directory injected into the sandbox:

- **`.bashrc`** — Custom PS1 with working directory and git branch, bash completion from the Nix store, colorized grep, `ll`/`la`/`l` aliases
- **`nix.conf`** — `experimental-features = nix-command flakes`, plus the grigio jcode binary cache substituter and trust key
- **`opencode/`** — Pre-configured with skills, AGENTS.md prompt instructions, and an opencode.jsonc config
- Runtime caches (`.cache`, `.npm`, `.local`, `.nix-profile`, etc.) are gitignored

## Adding tools to the sandbox

Edit [`flake.nix`](flake.nix) and add packages to the `mkShell` `packages` list, then run:

```bash
nix flake update    # update nixpkgs (optional)
```

## Updating nixpkgs and jcode

```bash
nix flake update
```

This updates `flake.lock` to the latest nixpkgs unstable commit and bumps the
`jcode` input (github:grigio/jcode, which provides the prebuilt jcode binary)
to the newest version.

CI also runs this automatically: the **daily flake.lock update** workflow runs
`nix flake update` every day, validates with `nix flake check --all-systems`,
smoke-tests the sandbox, regenerates the version badges from the new lock, and
merges everything through a PR. The badge workflow additionally refreshes the
badges on every push to `master`, so they always match the locked versions.

The pinned reasonix version in `flake.nix` is updated the same way: weekly the
**reasonix updater** workflow runs
[`scripts/update-reasonix.sh`](scripts/update-reasonix.sh), which queries the
latest `vX.Y.Z` CLI release on GitHub (the `desktop-v*` releases are a separate
desktop-app track and are skipped), rewrites the version/hash pins from the
release's `SHA256SUMS`, validates with `nix build .#reasonix`, and auto-merges
a PR after smoke-testing the sandbox and refreshing the badges. The maki pin is
kept current by the same pattern:
[`scripts/update-maki.sh`](scripts/update-maki.sh) runs weekly, validates with
`nix build .#maki`, and auto-merges a PR. To bump either tool manually, just
edit the `version` and `hash` lines in `flake.nix` or run
`bash scripts/update-reasonix.sh` / `bash scripts/update-maki.sh`.

## License

MIT — see [LICENSE](LICENSE).
