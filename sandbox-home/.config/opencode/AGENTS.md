
### Package installation
Nixpkgs channel is NOT configured. `nix-shell -p <pkg>` will fail.
Workaround: find binaries directly in Nix store:
  ls /nix/store/*/bin/<binary>   # e.g. ls /nix/store/*/bin/bun
Then use the full path: /nix/store/<hash>-<pkg>-<ver>/bin/<binary>

Modern `nix` CLI commands (e.g. `nix flake metadata`) require:
  --extra-experimental-features 'nix-command flakes'

No Nix channels or profiles are configured by default (`nix-channel --list` is empty, no system profile exists). Packages must be referenced by store path.

### System info
Host runs Linux but no native package manager binaries (pacman, apt, dnf, etc.) are available in the sandbox. Only Nix store binaries and statically-linked binaries work.

### Nix/bash completion quirk
The host bash (`/nix/store/*-bash-5.3p15/bin/bash`) is compiled **without programmable completion** — `complete` is not a builtin, `shopt -q progcomp` fails.

To get bash completion in the dev shell, use **both** in `flake.nix`:
- `pkgs.bashInteractive` — nixpkgs bash with programmable completion enabled
- `pkgs."bash-completion"` — completion definitions (note: quoted string attr due to hyphen)

`nix develop -c bash` resolves `bash` via PATH, which finds `bashInteractive`'s bin first (prepended by the devShell).

For `.bashrc` guards, check for `type complete &>/dev/null` rather than `[ -n "$BASH_VERSION" ]` — the host bash has `BASH_VERSION` set but lacks the `complete` builtin, so a version-only guard won't suppress errors from bash-completion's startup scripts.