{ inputs, self, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      inherit (inputs) nixpkgs;
      exports = { inherit (self) flakeModules lib nixosModules; };
      flakeParts = inputs.flake-parts;
      # Checks and focused evaluation share these evaluations.
      flakePartsExample = import ../examples/flake-parts {
        inherit
          exports
          flakeParts
          nixpkgs
          system
          ;
      };
      staticNixosExample = import ../examples/static-nixos {
        inherit exports nixpkgs system;
      };
      tests = import ../tests/evaluation.nix {
        inherit
          exports
          flakeParts
          flakePartsExample
          nixpkgs
          staticNixosExample
          system
          ;
        flake = self;
      };
    in
    {
      formatter = pkgs.callPackage ./formatter.nix { };
      devShells.default = pkgs.callPackage ./shell.nix {
        inherit (config) formatter;
      };
      checks = import ../tests {
        inherit
          flakeParts
          flakePartsExample
          nixpkgs
          pkgs
          system
          tests
          ;
        inherit (config) formatter;
      };
      legacyPackages = import ./legacy-packages.nix {
        inherit
          exports
          flakePartsExample
          nixpkgs
          staticNixosExample
          system
          tests
          ;
      };
    };
}
