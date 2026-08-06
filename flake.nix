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
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # Reference nixpkgs' own lazily-evaluated package set. All outputs share
      # the same per-system evaluation, unlike `import nixpkgs` which evaluates
      # the whole tree anew on every call.
      pkgsFor = system: nixpkgs.legacyPackages.${system};
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

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          # The grigio binary cache only publishes x86_64-linux, so jcode is a
          # pure download there. On other systems it would compile ~1000 crates
          # from source, which is not what this shell is for.
          jcode' = jcode.packages.${system}.default or null;
        in
        {
          default = pkgs.mkShell {
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
            ] ++ lib.optionals (system == "x86_64-linux") [ jcode' ]
            ++ [ bash-completion bashInteractive ];

            shellHook = ''
              export NIX_PATH=nixpkgs=${nixpkgs}
              echo "=== sandbox-bwrap-nix development shell ==="
              echo "  nixpkgs: nixpkgs-unstable (${self.inputs.nixpkgs.lastModifiedDate} - ${self.inputs.nixpkgs.shortRev})"
            '';

            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        });
    };
}
