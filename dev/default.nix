{ nixpkgs, systems }:
let
  forAllSystems = nixpkgs.lib.genAttrs systems;
  flakePartsExample = import ../tests/flake-parts-example.nix { inherit nixpkgs; };
  library = import ./library.nix { inherit flakePartsExample nixpkgs systems; };
  formatter = forAllSystems (
    system: nixpkgs.legacyPackages.${system}.callPackage ./formatter.nix { }
  );
in
{
  inherit formatter;
  lib = library;
  devShells = forAllSystems (system: {
    default = nixpkgs.legacyPackages.${system}.callPackage ./shell.nix {
      formatter = formatter.${system};
    };
  });
  checks = forAllSystems (
    system:
    import ../tests/checks.nix {
      inherit flakePartsExample nixpkgs system;
      pkgs = nixpkgs.legacyPackages.${system};
      formatter = formatter.${system};
      tests = library.tests.${system};
    }
  );
}
