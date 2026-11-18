{
  description = "Nix packages for upstream CLI releases";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              package:
              builtins.elem (nixpkgs.lib.getName package) [
                "antigravity-cli"
                "gencode"
              ];
          };
        in
        {
          genspark-cli = pkgs.callPackage ./nix/pkgs/genspark-cli.nix { };
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          herdr-core = pkgs.callPackage ./nix/pkgs/herdr-core.nix { };
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          antigravity-cli = pkgs.callPackage ./nix/pkgs/antigravity-cli.nix { };
          gencode = pkgs.callPackage ./nix/pkgs/gencode.nix { };
          supabase-cli = pkgs.callPackage ./nix/pkgs/supabase-cli.nix { };
        }
      );
      checks = self.packages;
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
