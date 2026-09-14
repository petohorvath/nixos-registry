# Development inputs stay outside the consumer-facing flake.
{
  description = "nixos-registry development and evaluation checks";

  inputs = {
    registry.url = "path:..";
    nixpkgsStable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgsUnstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      registry,
      nixpkgsStable,
      nixpkgsUnstable,
      ...
    }:
    let
      libraries = {
        stable = nixpkgsStable.lib;
        unstable = nixpkgsUnstable.lib;
      };
      tests = evalWithLibraries ../tests;
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
        partialContributions = evalWithLibraries ../examples/plain-nix/partial-contributions.nix;
        scalarConflicts = evalWithLibraries ../examples/plain-nix/scalar-conflict.nix;
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
      );

      formatter = forAllSystems (system: nixpkgsStable.legacyPackages.${system}.nixfmt);
    };
}
