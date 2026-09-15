# Development inputs stay outside the consumer-facing flake.
{
  description = "nixos-registry development and evaluation checks";

  inputs = {
    registry.url = "path:..";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flakePartsExampleStable = {
      url = "path:../examples/flake-parts";
      inputs.nixpkgs.follows = "nixpkgsStable";
      inputs.nixos-registry.follows = "registry";
    };
    flakePartsExampleUnstable = {
      url = "path:../examples/flake-parts";
      inputs.nixpkgs.follows = "nixpkgsUnstable";
      inputs.nixos-registry.follows = "registry";
    };
  };

  outputs =
    {
      registry,
      nixpkgsStable,
      nixpkgsUnstable,
      flakePartsExampleStable,
      flakePartsExampleUnstable,
      ...
    }:
    let
      sources = {
        stable = nixpkgsStable;
        unstable = nixpkgsUnstable;
      };
      libraries = builtins.mapAttrs (_: source: source.lib) sources;
      flakePartsExamples = {
        stable = flakePartsExampleStable;
        unstable = flakePartsExampleUnstable;
      };
      tests = builtins.mapAttrs (
        channel: nixpkgs:
        import ../tests {
          inherit nixpkgs;
          alternateNixpkgs = if channel == "stable" then nixpkgsUnstable else nixpkgsStable;
          flakePartsExample = flakePartsExamples.${channel};
          inherit (registry.lib) mkRegistry;
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
            inherit lib;
            inherit (registry.lib) mkRegistry;
          }
        ) libraries;
      forAllSystems = nixpkgsStable.lib.genAttrs systems;
    in
    {
      lib = {
        inherit tests;
        examples = evalWithLibraries ../examples/plain-nix;
        collectionLaziness = evalWithLibraries ../examples/plain-nix/collection-laziness.nix;
        combinedReads = evalWithLibraries ../examples/plain-nix/combined-reads.nix;
        conditionalOrdering = evalWithLibraries ../examples/plain-nix/conditional-ordering.nix;
        flakePartsExamples = builtins.mapAttrs (_: example: example.lib.result) flakePartsExamples;
        nixosExamples = builtins.mapAttrs (
          _: nixpkgs:
          (import ../examples/nixos {
            inherit nixpkgs;
            inherit (registry.lib) mkRegistry;
          }).result
        ) sources;
        partialContributions = evalWithLibraries ../examples/plain-nix/partial-contributions.nix;
        priorities = evalWithLibraries ../examples/plain-nix/priorities.nix;
        scalarConflicts = evalWithLibraries ../examples/plain-nix/scalar-conflict.nix;
        valueCycles = evalWithLibraries ../examples/plain-nix/value-cycle.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgsStable.legacyPackages.${system};
        in
        builtins.mapAttrs (
          channel: results:
          assert builtins.deepSeq results true;
          pkgs.runCommand "registry-${channel}" { } ''
            touch "$out"
          ''
        ) tests
        // nixpkgsStable.lib.mapAttrs' (
          channel: example:
          nixpkgsStable.lib.nameValuePair "flake-parts-${channel}" example.checks.${system}.registry
        ) flakePartsExamples
        // nixpkgsStable.lib.concatMapAttrs (
          channel: source:
          nixpkgsStable.lib.mapAttrs'
            (
              name: script:
              nixpkgsStable.lib.nameValuePair "${name}-${channel}" (
                pkgs.runCommand "registry-${name}-${channel}" { nativeBuildInputs = [ pkgs.nix ]; } ''
                  bash ${script} ${source}/lib ${registry} ${../tests}
                  touch "$out"
                ''
              )
            )
            {
              diagnostics = ../tests/diagnostics.sh;
              ordering = ../tests/ordering-failures.sh;
              recursion = ../tests/recursion.sh;
            }
        ) sources
      );

      formatter = forAllSystems (system: nixpkgsStable.legacyPackages.${system}.nixfmt);
    };
}
