{
  description = "sandbox-bwrap-nix development environment";

  # jcode is a prebuilt binary from the grigio Nix binary cache
  # (https://grigio.github.io/jcode, install docs: https://github.com/grigio/jcode#install-flake).
  # Applying these settings means `nix develop`, `nix build` and `nix flake check`
  # in this repo download jcode and its crane dependency layer instead of
  # compiling ~1000 crates from source.
  nixConfig = {
    extra-substituters = [ "https://grigio.github.io/jcode" ];
    extra-trusted-public-keys = [ "grigio-jcode:WdqguwKdwOilH+ITvLO98qZy9x5HQ8Cl0xltHtSsUvQ=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # jcode is a prebuilt binary from the grigio Nix binary cache (https://grigio.github.io/jcode, install docs: https://github.com/grigio/jcode#install-flake).
    jcode.url = "github:grigio/jcode";
  };

  outputs = { self, nixpkgs, jcode }:
    let
      # x86_64-linux only: the jcode binary cache is
      # x86-64 only, and CI runs on x86_64 runners.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # DeepSeek Harness (https://github.com/deepseek-ai/deepseek-harness), the
      # `dsh` CLI from deepseek-ai. Upstream distributes it as the public npm
      # package @deepseek-ai/dsh (no GitHub releases or prebuilt nix binaries),
      # so we wrap the published tarball with nixpkgs' buildNpmPackage.
      # The published tarball ships no package-lock.json, so a lock generated
      # from the tarball at this version is vendored under vendor/dsh/ (and
      # tidied with `npm install --package-lock-only --ignore-scripts`).
      # DeepSeek Harness is in rapid developer preview and `master` moves
      # hourly, but the npm package version is the stable unit to pin. The
      # version/hash pins below are kept current by scripts/update-dsh.sh, run
      # weekly by .github/workflows/update-dsh.yml.
      deepseekHarnessFor =
        let
          version = "0.1.1-rc.2";
          dshLock = ./vendor/dsh/package-lock.json;
        in
        pkgs.buildNpmPackage.override { nodejs = pkgs.nodejs_24; } (finalAttrs: {
          pname = "deepseek-harness";
          inherit version;
          description = "DeepSeek Harness (dsh): everything-is-a-plugin agent harness";
          homepage = "https://github.com/deepseek-ai/deepseek-harness";
          meta = {
            license = pkgs.lib.licenses.mit;
            mainProgram = "dsh";
            platforms = pkgs.nodejs_24.meta.platforms;
          };

          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${finalAttrs.version}.tgz";
            hash = "sha256-R+wF9FraWrh3ea4YqQRWtev/VCHcD/XBeWd9ZeHBYFc=";
          };

          postPatch = ''
            cp ${dshLock} ./package-lock.json
          '';

          npmDepsHash = "sha256-tnDkIhvy+3bKu8ores29ZnrXtJjP71CR8+YLUbYtclc=";

          # The published package ships prebuilt lib/ JS; there is nothing to
          # compile. Native addons (node-pty, koffi) are still built by
          # npmRebuild during the install phase.
          dontBuild = true;

          # Runtime needs the Node internal loader (used by the HMR plugin),
          # which is only reachable with --expose-internals.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postInstall = ''
            mkdir -p $out/bin
            makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/dsh \
              --add-flags --expose-internals \
              --add-flags $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js
            # Convenience alias to the package name (the upstream binary is
            # `dsh`).
            ln -s dsh $out/bin/deepseek-harness
          '';

          # The package ships no test suite; the sandbox smoke test exercises
          # `dsh --version` via start-sandbox.sh.
          doCheck = false;
        });
    in
    {
      # `nix fmt` formats flake.nix with nixpkgs-fmt
      formatter.${system} = pkgs.nixpkgs-fmt;

      checks.${system} = {
        # Building the dev shell exercises the whole tool set, including
        # jcode from the grigio binary cache.
        default = self.devShells.${system}.default;
        # Building the dsh npm wrap validates the npm version/hash pins and
        # the vendored package-lock (a wrong pin fails the fixed-output
        # fetch, and the vendored lock must match the src package.json).
        deepseek-harness = self.packages.${system}.deepseek-harness;
        # Formatting gate: `nix flake check` (and CI) fail if flake.nix is
        # not nixpkgs-fmt clean. `nix fmt` normalizes it locally.
        fmt = pkgs.runCommand "check-nixpkgs-fmt" { src = self; } ''
          set -e
          ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check $src/flake.nix
          touch $out
        '';
      };

      packages.${system} = {
        deepseek-harness = deepseekHarnessFor;
      };

      devShells.${system} =
        let
          deepseek-harness = deepseekHarnessFor;
          # jcode comes prebuilt from the grigio binary cache; this flake only
          # targets x86_64-linux, where the cache makes it a pure download.
          jcode' = jcode.packages.${system}.default or null;
        in
        {
          default = pkgs.mkShell {
            shell = pkgs.bashInteractive;
            # These are the packages you always need in the sandbox
            packages = with pkgs; [
              nix
              cacert
              curl

              git
              bun
              uv
              gnumake
              jq

              herdr
              micro
              less
              fd
              ripgrep
              # process inspection for debugging inside the sandbox
              procps
              # binary inspection/unpacking (e.g. Firefox extension zips)
              unzip
              # classic `which`; some build scripts and agents still rely on it
              which
              btop
              # clear and reset terminal commands
              ncurses
              cargo
              yt-dlp
              opencode
              pi-coding-agent
              deepseek-harness
              codex
              # Browser support: Firefox's GUI needs XKB keyboard rules and
              # fontconfig config, which `--clearenv` in start-sandbox.sh strips
              # out of the host environment. Without these, Firefox crashes on
              # launch with "Failed to create XKB keymap", which breaks the
              # jcode browser tool's Firefox agent bridge.
              xkeyboard-config
              fontconfig

              # GTK GUI rendering: GTK/gdk-pixbuf also needs a shared-mime-info
              # database and an icon theme. start-sandbox.sh binds the host's
              # /usr/share (mime DB + icon themes + fonts + locale), but on
              # minimal/NixOS hosts that tree may not exist, so we ship our own
              # copies from the nix store and expose them through XDG_DATA_DIRS.
              # gdk-pixbuf is listed explicitly because the shellHook references
              # ${pkgs.gdk-pixbuf}/share for its pixbuf loaders.
              shared-mime-info
              hicolor-icon-theme
              gdk-pixbuf
              bash-completion
              bashInteractive
            ] ++ lib.optionals (jcode' != null) [ jcode' ];

            shellHook = ''
              export SHELL=${pkgs.bashInteractive}/bin/bash
              export NIX_PATH=nixpkgs=${nixpkgs}
              # Point GTK/xkbcommon at the XKB data so Firefox can build its
              # keymap in the sandbox (see packages list above).
              export XKB_CONFIG_ROOT=${pkgs.xkeyboard-config}/share/X11/xkb
              export FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf
              export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts
              # Add nix-provided icon theme + shared-mime-info, then the host's
              # /usr/share (bound by start-sandbox.sh). This fixes "Could not
              # load a pixbuf ... pixbuf loaders or the mime database could not
              # be found" from GTK under --clearenv.
              export XDG_DATA_DIRS=${pkgs.hicolor-icon-theme}/share:${pkgs.shared-mime-info}/share:${pkgs.gdk-pixbuf}/share:/usr/share
              echo "=== sandbox-bwrap-nix development shell ==="
              echo "  nixpkgs: nixpkgs-unstable (${self.inputs.nixpkgs.lastModifiedDate} - ${self.inputs.nixpkgs.shortRev})"
              echo "  XKB_CONFIG_ROOT=$XKB_CONFIG_ROOT"
            '';

            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            # Some clients (curl, node, git) read the bundle from this var
            # rather than SSL_CERT_FILE; set both for robustness.
            CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        };
    };
}
