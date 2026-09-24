# Evaluate examples with the root selection; no extra flake or lock is needed.
{
  nixpkgs ? (builtins.getFlake (toString ../.)).inputs.nixpkgs,
  system ? builtins.currentSystem,
}:
let
  inherit (import ../lib) mkRegistry;
  flakePartsExample = import ../examples/flake-parts/evaluate.nix { inherit nixpkgs; };
  evalExample =
    modulePath:
    import modulePath {
      inherit (nixpkgs) lib;
      inherit mkRegistry;
    };
in
{
  plainNix = evalExample ./plain-nix;
  collectionLaziness = evalExample ./plain-nix/collection-laziness.nix;
  combinedReads = evalExample ./plain-nix/combined-reads.nix;
  conditionalOrdering = evalExample ./plain-nix/conditional-ordering.nix;
  flakeParts = flakePartsExample.lib.result;
  nixos = (import ./nixos { inherit mkRegistry nixpkgs system; }).result;
  staticNixos = (import ./static-nixos { inherit nixpkgs system; }).result;
  partialContributions = evalExample ./plain-nix/partial-contributions.nix;
  priorities = evalExample ./plain-nix/priorities.nix;
  scalarConflicts = evalExample ./plain-nix/scalar-conflict.nix;
  valueCycles = evalExample ./plain-nix/value-cycle.nix;
}
