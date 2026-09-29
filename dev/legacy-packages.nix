# Focused evaluation of the test suite and example results.
{
  exports,
  flakePartsExample,
  nixpkgs,
  staticNixosExample,
  system,
  tests,
}:
let
  inherit (nixpkgs) lib;
  inherit (exports.lib) mkRegistry;
  evalPlainExample = path: import path { inherit lib mkRegistry; };
in
{
  inherit tests;

  examples = {
    default = evalPlainExample ../examples/plain-nix;
    collectionLaziness = evalPlainExample ../examples/plain-nix/collection-laziness.nix;
    combinedReads = evalPlainExample ../examples/plain-nix/combined-reads.nix;
    conditionalOrdering = evalPlainExample ../examples/plain-nix/conditional-ordering.nix;
    partialContributions = evalPlainExample ../examples/plain-nix/partial-contributions.nix;
    priorities = evalPlainExample ../examples/plain-nix/priorities.nix;
    scalarConflicts = evalPlainExample ../examples/plain-nix/scalar-conflict.nix;
    valueCycles = evalPlainExample ../examples/plain-nix/value-cycle.nix;
    flakeParts = flakePartsExample.lib.result;
    nixos = (import ../examples/nixos { inherit mkRegistry nixpkgs system; }).result;
    staticNixos = staticNixosExample.result;
  };
}
