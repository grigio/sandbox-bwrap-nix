{
  description = "sandbox-bwrap-nix development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/7525d999cd850b9a488817abc89c75dc733acf17";
  };

  outputs = { self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: builtins.foldl' (acc: system: acc // { ${system} = f system; }) {} systems;

    pkgsFor = system: import nixpkgs { inherit system; };
  in {
    formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);

    checks = forAllSystems (system: {
      default = self.devShells.${system}.default;
    });

    devShells = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
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

          micro
          less
          fd
          ripgrep
          opencode
        ] ++ [ pkgs."bash-completion" pkgs.bashInteractive ];

        shellHook = ''
          export NIX_PATH=nixpkgs=${nixpkgs}
          echo "=== sandbox-bwrap-nix development shell ==="
          echo "  nixpkgs: nixpkgs-unstable (commit 7525d99)"
          echo "  tools: nix, git, bun, curl, uv, make, opencode"
        '';

        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    });
  };
}
