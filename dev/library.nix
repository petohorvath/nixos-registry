{
  flakePartsExample,
  nixpkgs,
  systems,
}:
let
  mkRegistry = import ../lib/mk-registry.nix;
  forAllSystems = nixpkgs.lib.genAttrs systems;
  tests = forAllSystems (
    system:
    import ../tests {
      inherit
        flakePartsExample
        mkRegistry
        nixpkgs
        system
        ;
    }
  );
  evalExample =
    modulePath:
    import modulePath {
      inherit (nixpkgs) lib;
      inherit mkRegistry;
    };
in
{
  inherit tests;
  examples = evalExample ../examples/plain-nix;
  collectionLaziness = evalExample ../examples/plain-nix/collection-laziness.nix;
  combinedReads = evalExample ../examples/plain-nix/combined-reads.nix;
  conditionalOrdering = evalExample ../examples/plain-nix/conditional-ordering.nix;
  flakePartsExamples = flakePartsExample.lib.result;
  nixosExamples = forAllSystems (
    system:
    (import ../examples/nixos {
      inherit mkRegistry nixpkgs system;
    }).result
  );
  staticNixosExamples = forAllSystems (
    system: (import ../examples/static-nixos { inherit nixpkgs system; }).result
  );
  partialContributions = evalExample ../examples/plain-nix/partial-contributions.nix;
  priorities = evalExample ../examples/plain-nix/priorities.nix;
  scalarConflicts = evalExample ../examples/plain-nix/scalar-conflict.nix;
  valueCycles = evalExample ../examples/plain-nix/value-cycle.nix;
}
