# sandbox-bwrap-nix

Run Nix commands in a lightweight bubblewrap sandbox.

Isolates Nix operations from your host filesystem while preserving access to `/nix/store` and `/nix/var/nix`. Useful for safely experimenting with Nix builds, running [OpenCode](https://opencode.ai) in a sandbox, or containing AI coding tools.

## Quick start

```bash
./start-sandbox.sh
```

This drops you into a sandboxed bash shell with Nix, git, bun, uv, and other tools pre-installed. The sandbox-home directory acts as `$HOME`.

## Installation

Add a persistent alias to your shell config (e.g. `~/.bashrc` or `~/.zshrc`):

```bash
alias sss=/path/to/sandbox-bwrap-nix/start-sandbox.sh
```

Replace `/path/to/sandbox-bwrap-nix` with the absolute path to this directory (use `pwd` to get it). After adding the line, reload with `source ~/.bashrc` (or open a new terminal), then launch with `sss`.

## How it works

[`start-sandbox.sh`](start-sandbox.sh) invokes `bwrap` with:

| Mount | Type | Purpose |
|-------|------|---------|
| `/nix/store`, `/nix/var/nix` | bind (ro) | Nix store access |
| `/nix/var/nix/builds` | tmpfs | Isolate builds |
| `/bin/sh`, `/bin/bash`, `/usr/bin/nix` | bind (ro) | Essential binaries |
| `/usr/lib`, `/usr/lib64` | bind | Shared libraries |
| `/etc/resolv.conf`, `/etc/hosts`, `/etc/nsswitch.conf` | bind (ro) | DNS / name resolution |
| SSL certs | bind (ro) | HTTPS support |
| `sandbox-home/` | bind | Isolated home dir |
| `/tmp` | tmpfs | Temporary files |
| `/proc`, `/dev` | bind | Process / device access |

The environment is cleared (`--clearenv`), networking is shared (`--share-net`), and PID namespace is unshared (`--unshare-pid`).

Inside the sandbox, `nix develop` with the [flake](flake.nix) provisions a dev shell containing: **nix, git, bun, uv, opencode, gnumake, micro, less**, and bash completion.

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

## Requirements

- Linux with [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`) installed
- Nix with flakes and `nix-command` enabled on the host

## Project structure

```
├── start-sandbox.sh        # Entry point — invokes bwrap
├── flake.nix               # Nix flake with dev shell definition
├── flake.lock              # Pinned nixpkgs revision
├── sandbox-home/           # Isolated home directory
│   ├── .bashrc             # Colored prompt, git branch, aliases
│   ├── .bash_profile       # Sources .bashrc
│   ├── SANDBOX             # Marker file (empty)
│   └── .config/
│       ├── nix/nix.conf    # Enables flakes + nix-command
│       └── opencode/       # OpenCode config (skills, AGENTS.md)
├── .gitignore              # Ignores generated runtime artifacts
└── README.md
```

## sandbox-home

A minimal home directory injected into the sandbox:

- **`.bashrc`** — Custom PS1 with working directory and git branch, bash completion from the Nix store, colorized grep, `ll`/`la`/`l` aliases
- **`nix.conf`** — `experimental-features = nix-command flakes`
- **`opencode/`** — Pre-configured with skills, AGENTS.md prompt instructions, and an opencode.jsonc config
- Runtime caches (`.cache`, `.npm`, `.local`, `.nix-profile`, etc.) are gitignored

## Adding tools to the sandbox

Edit [`flake.nix`](flake.nix) and add packages to the `mkShell` `packages` list, then run:

```bash
nix flake update    # update nixpkgs (optional)
```

## Updating nixpkgs

```bash
nix flake update
```

This updates `flake.lock` to the latest nixpkgs unstable commit.
