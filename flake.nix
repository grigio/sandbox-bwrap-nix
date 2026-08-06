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
      reasonixFor = system:
        let
          pkgs = pkgsFor system;
          version = "1.20.0";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "reasonix";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-amd64.tar.gz";
            hash = "sha256-eWH1l1zpWjXbptHgGbxM7R9rZ73C2fsMneAsI+kUeVY=";
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
      });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          # reasonix is packaged by this flake (see `packages`), not nixpkgs
          reasonix = self.packages.${system}.reasonix;
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
              btop
              # clear and reset terminal commands
              ncurses
              cargo
              yt-dlp
              opencode
              pi-coding-agent
              reasonix
            ] ++ lib.optionals (jcode' != null) [ jcode' ]
            ++ [ bash-completion bashInteractive ];

            shellHook = ''
              export SHELL=${pkgs.bashInteractive}/bin/bash
              export NIX_PATH=nixpkgs=${nixpkgs}
              echo "=== sandbox-bwrap-nix development shell ==="
              echo "  nixpkgs: nixpkgs-unstable (${self.inputs.nixpkgs.lastModifiedDate} - ${self.inputs.nixpkgs.shortRev})"
            '';

            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        });
    };
}
