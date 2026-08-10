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
    # jcode, prebuilt via the grigio Nix binary cache (https://grigio.github.io/jcode)
    jcode.url = "github:grigio/jcode";
  };

  outputs = { self, nixpkgs, jcode }:
    let
      # x86_64-linux only: reasonix and the jcode binary cache are
      # x86-64 only, and CI runs on x86_64 runners.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # Reference nixpkgs' own lazily-evaluated package set. All outputs share
      # the same per-system evaluation, unlike `import nixpkgs` which evaluates
      # the whole tree anew on every call.
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Reasonix CLI is shipped as a statically linked Go binary in a flat
      # tarball per platform on GitHub Releases, so packaging it is a pure
      # download + install. No build steps and no runtime deps.
      # Only the x86-64 (amd64) build is used: the flake targets x86_64-linux.
      # The version/hash pins below are kept current by
      # scripts/update-reasonix.sh, run every two hours by
      # .github/workflows/update-reasonix.yml.
      reasonixFor = system:
        let
          pkgs = pkgsFor system;
          version = "1.21.3";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "reasonix";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-amd64.tar.gz";
            hash = "sha256-yxKcPgXYqrOSb+SEnmjco5y+dEBHhYQnKml7Vh2N4EE=";
          };
          # The tarball has no wrapping directory, so files land at the top
          # level of the build dir.
          sourceRoot = ".";
          installPhase = ''
            runHook preInstall
            install -Dm755 reasonix $out/bin/reasonix
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "DeepSeek-native AI coding agent for your terminal";
            homepage = "https://github.com/esengine/DeepSeek-Reasonix";
            license = licenses.mit;
            mainProgram = "reasonix";
            platforms = [ "x86_64-linux" ];
          };
        };

      # Maki (https://github.com/tontinton/maki) is an AI coding agent shipped
      # as a statically linked musl binary in a flat tarball per platform on
      # GitHub Releases, so packaging it is a pure download + install. No
      # build steps and no runtime deps (statically linked).
      # Only the x86-64 build is used: the flake targets x86_64-linux.
      # The version/hash pins below are kept current by
      # scripts/update-maki.sh, run weekly by
      # .github/workflows/update-maki.yml.
      makiFor = system:
        let
          pkgs = pkgsFor system;
          version = "0.4.5";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "maki";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://github.com/tontinton/maki/releases/download/v${version}/maki-v${version}-x86_64-unknown-linux-musl.tar.gz";
            hash = "sha256-MWpGpcs292gyQBVQve3AlSOiZCWebIwOmiQKVpcrJDE";
          };
          # The tarball has no wrapping directory, so the binary lands at the
          # top level of the build dir.
          sourceRoot = ".";
          installPhase = ''
            runHook preInstall
            install -Dm755 maki $out/bin/maki
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "An efficient AI coding agent extendable by neovim like Lua plugins";
            homepage = "https://github.com/tontinton/maki";
            license = licenses.mit;
            mainProgram = "maki";
            platforms = [ "x86_64-linux" ];
          };
        };
    in
    {
      # `nix fmt` formats flake.nix with nixpkgs-fmt
      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = self.devShells.${system}.default;
          # Formatting gate: `nix flake check` (and CI) fail if flake.nix is
          # not nixpkgs-fmt clean. `nix fmt` normalizes it locally.
          fmt = pkgs.runCommand "check-nixpkgs-fmt" { src = self; } ''
            set -e
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check $src/flake.nix
            touch $out
          '';
        });

      # `nix build .#reasonix`, `nix run .#reasonix`, or `nix profile install`
      packages = forAllSystems (system: {
        reasonix = reasonixFor system;
        maki = makiFor system;
      });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          # reasonix and maki are packaged by this flake (see `packages`),
          # not nixpkgs
          reasonix = self.packages.${system}.reasonix;
          maki = self.packages.${system}.maki;
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
              reasonix
              maki
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
            ] ++ lib.optionals (jcode' != null) [ jcode' ]
            ++ [ bash-completion bashInteractive ];

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
        });
    };
}
