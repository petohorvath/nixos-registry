# Strict collection reads and cyclic values recurse through the constructor.
{ lib, registryLib, ... }:
let
  inherit (registryLib) mkRegistry;
  collectionLaziness = import ../../examples/plain-nix/collection-laziness.nix {
    inherit lib mkRegistry;
  };
  valueCycle = import ../../examples/plain-nix/value-cycle.nix { inherit lib mkRegistry; };
  recurses = expr: {
    inherit expr;
    expectedError = {
      type = "EvalError";
      msg = "infinite recursion encountered";
    };
  };
in
{
  testStrictCollectionCombinedRead = recurses collectionLaziness.strict.combined.settings.domain;
  testStrictCollectionValidation = recurses collectionLaziness.strict.validate;
  testValueCycleCombinedRead = recurses valueCycle.combined.services.east;
  testValueCycleValidation = recurses valueCycle.validate;
}
