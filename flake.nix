# Typed shared data with root development tools and evaluation checks.
{
  description = "Typed shared data across Nix configurations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    inputs:
    let
      inherit (inputs) nixpkgs;
      mkRegistry = import ./lib/mk-registry.nix;
      flakePartsExample = import ./tests/flake-parts-example.nix { inherit nixpkgs; };
      tests = forAllSystems (
        system:
        import ./tests {
          inherit
            flakePartsExample
            mkRegistry
            nixpkgs
            system
            ;
        }
      );
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      evalExample =
        modulePath:
        import modulePath {
          inherit (nixpkgs) lib;
          inherit mkRegistry;
        };
      forAllSystems = nixpkgs.lib.genAttrs systems;
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
              flakePartsExample
              formatter
              nixpkgs
              pkgs
              system
              ;
            tests = tests.${system};
          };
        }
      );
    in
    {
      flakeModules.default = import ./modules/flake.nix;
      nixosModules.default = import ./modules/nixos.nix;

      lib = {
        inherit mkRegistry tests;
        examples = evalExample ./examples/plain-nix;
        collectionLaziness = evalExample ./examples/plain-nix/collection-laziness.nix;
        combinedReads = evalExample ./examples/plain-nix/combined-reads.nix;
        conditionalOrdering = evalExample ./examples/plain-nix/conditional-ordering.nix;
        flakePartsExamples = flakePartsExample.lib.result;
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
