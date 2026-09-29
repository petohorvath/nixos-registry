# Focused evaluation of the test suite and example results.
{
  inputs,
  self,
  system,
}:
let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;
  inherit (self.lib) mkRegistry;
  flakeParts = inputs.flake-parts;
  evalPlainExample = path: import path { inherit lib mkRegistry; };
in
{
  tests = import ../tests/evaluation.nix {
    inherit flakeParts nixpkgs system;
    flake = self;
  };

  examples = {
    default = evalPlainExample ../examples/plain-nix;
    collectionLaziness = evalPlainExample ../examples/plain-nix/collection-laziness.nix;
    combinedReads = evalPlainExample ../examples/plain-nix/combined-reads.nix;
    conditionalOrdering = evalPlainExample ../examples/plain-nix/conditional-ordering.nix;
    partialContributions = evalPlainExample ../examples/plain-nix/partial-contributions.nix;
    priorities = evalPlainExample ../examples/plain-nix/priorities.nix;
    scalarConflicts = evalPlainExample ../examples/plain-nix/scalar-conflict.nix;
    valueCycles = evalPlainExample ../examples/plain-nix/value-cycle.nix;
    flakeParts =
      (import ../examples/flake-parts {
        inherit flakeParts nixpkgs system;
        registry = self;
      }).lib.result;
    nixos = (import ../examples/nixos { inherit mkRegistry nixpkgs system; }).result;
    staticNixos =
      (import ../examples/static-nixos {
        inherit nixpkgs system;
        registry = self;
      }).result;
  };
}
