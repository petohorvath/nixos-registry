# Typed shared data with root development tools and evaluation checks.
{
  description = "Typed shared data across Nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flakePartsExampleStable = {
      url = "path:./examples/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flakePartsExampleUnstable = {
      url = "path:./examples/flake-parts";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    inputs:
    let
      inherit (inputs)
        flakePartsExampleStable
        flakePartsExampleUnstable
        nixpkgs
        nixpkgs-unstable
        ;
      mkRegistry = import ./lib/mk-registry.nix;
      sources = {
        stable = nixpkgs;
        unstable = nixpkgs-unstable;
      };
      libraries = builtins.mapAttrs (_: source: source.lib) sources;
      flakePartsExamples = {
        stable = flakePartsExampleStable;
        unstable = flakePartsExampleUnstable;
      };
      tests = builtins.mapAttrs (
        channel: nixpkgs:
        import ./tests {
          inherit mkRegistry nixpkgs;
          alternateNixpkgs = if channel == "stable" then inputs.nixpkgs-unstable else inputs.nixpkgs;
          flakePartsExample = flakePartsExamples.${channel};
        }
      ) sources;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      evalWithLibraries =
        modulePath:
        builtins.mapAttrs (
          _: lib:
          import modulePath {
            inherit lib mkRegistry;
          }
        ) libraries;
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
              flakePartsExamples
              formatter
              pkgs
              sources
              system
              tests
              ;
          };
        }
      );
    in
    {
      lib = {
        inherit mkRegistry tests;
        examples = evalWithLibraries ./examples/plain-nix;
        collectionLaziness = evalWithLibraries ./examples/plain-nix/collection-laziness.nix;
        combinedReads = evalWithLibraries ./examples/plain-nix/combined-reads.nix;
        conditionalOrdering = evalWithLibraries ./examples/plain-nix/conditional-ordering.nix;
        flakePartsExamples = builtins.mapAttrs (_: example: example.lib.result) flakePartsExamples;
        nixosExamples = builtins.mapAttrs (
          _: nixpkgs:
          (import ./examples/nixos {
            inherit mkRegistry nixpkgs;
          }).result
        ) sources;
        partialContributions = evalWithLibraries ./examples/plain-nix/partial-contributions.nix;
        priorities = evalWithLibraries ./examples/plain-nix/priorities.nix;
        scalarConflicts = evalWithLibraries ./examples/plain-nix/scalar-conflict.nix;
        valueCycles = evalWithLibraries ./examples/plain-nix/value-cycle.nix;
      };

      devShells = forAllSystems (system: {
        default = development.${system}.shell;
      });
      formatter = forAllSystems (system: development.${system}.formatter);
      checks = forAllSystems (system: development.${system}.checks);
    };
}
