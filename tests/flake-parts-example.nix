# Exercise the example with the selected module system and its locked flake-parts source.
{ nixpkgs }:
let
  lock = builtins.fromJSON (builtins.readFile ../examples/flake-parts/flake.lock);
  flakePartsSource = builtins.fetchTree lock.nodes.flake-parts.locked;
  flakeParts =
    flakePartsSource
    // (import "${flakePartsSource}/flake.nix").outputs {
      self = flakeParts;
      nixpkgs-lib = nixpkgs;
    };
  example = {
    outPath = ../examples/flake-parts;
    inputs = exampleInputs;
  }
  // (import ../examples/flake-parts/flake.nix).outputs (
    exampleInputs
    // {
      self = example;
    }
  );
  exampleInputs = {
    inherit nixpkgs;
    flake-parts = flakeParts;
    nixos-registry = ../.;
    servicePublisher = (import ../examples/sources/service-publisher/flake.nix).outputs { };
    backupClient = (import ../examples/sources/backup-client/flake.nix).outputs { };
  };
in
example
