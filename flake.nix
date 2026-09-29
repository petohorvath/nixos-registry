/*
  Typed shared data across Nix configurations, with root development tools
  and evaluation checks.
*/
{
  description = "Typed shared data across Nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      # The constructor and static modules never read these inputs, so
      # plain import through outputs { } keeps working.
      inherit (inputs) flake-parts nixpkgs;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      exports = {
        lib = import ./lib;
        nixosModules.default = import ./nixos/module.nix;
        flakeModules.default = import ./flake-module.nix;
      };
      inherit (exports.lib) mkRegistry;
      evalExample =
        modulePath:
        import modulePath {
          inherit (nixpkgs) lib;
          inherit mkRegistry;
        };
      evalFlakePartsExample =
        system:
        import ./examples/flake-parts {
          inherit nixpkgs system;
          registry = exports;
          flakeParts = flake-parts;
        };
      tests = forAllSystems (
        system:
        import ./tests {
          inherit exports nixpkgs system;
          flakeParts = flake-parts;
        }
      );
      development = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          formatter = pkgs.callPackage ./formatter.nix { };
        in
        {
          inherit formatter;
          shell = pkgs.callPackage ./shell.nix { inherit formatter; };
          checks = import ./tests/checks.nix {
            inherit
              formatter
              nixpkgs
              pkgs
              system
              ;
            tests = tests.${system};
            flakeParts = flake-parts;
            flakePartsExample = evalFlakePartsExample system;
          };
        }
      );
    in
    {
      inherit (exports) flakeModules nixosModules;

      lib = exports.lib // {
        inherit tests;
        examples = evalExample ./examples/plain-nix;
        collectionLaziness = evalExample ./examples/plain-nix/collection-laziness.nix;
        combinedReads = evalExample ./examples/plain-nix/combined-reads.nix;
        conditionalOrdering = evalExample ./examples/plain-nix/conditional-ordering.nix;
        flakePartsExamples = (evalFlakePartsExample "x86_64-linux").lib.result;
        nixosExamples = forAllSystems (
          system:
          (import ./examples/nixos {
            inherit mkRegistry nixpkgs system;
          }).result
        );
        staticNixosExamples = forAllSystems (
          system: (import ./examples/static-nixos { inherit nixpkgs system; }).result
        );
        partialContributions = evalExample ./examples/plain-nix/partial-contributions.nix;
        priorities = evalExample ./examples/plain-nix/priorities.nix;
        scalarConflicts = evalExample ./examples/plain-nix/scalar-conflict.nix;
        valueCycles = evalExample ./examples/plain-nix/value-cycle.nix;
      };

      devShells = forAllSystems (system: {
        default = development.${system}.shell;
      });
      formatter = forAllSystems (system: development.${system}.formatter);
      checks = forAllSystems (system: development.${system}.checks);
    };
}
