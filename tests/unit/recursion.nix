# Strict collection reads and cyclic values recurse through the constructor.
{ fixtures, ... }:
let
  collectionLaziness = fixtures.examples.collection-laziness;
  nodeReferences = fixtures.examples.node-references;
  valueCycle = fixtures.examples.value-cycle;
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
  testCopiesKeyedThroughReferencesRecurse = recurses nodeReferences.keyedThroughReferences.tokens.east;
  testValueCycleCombinedRead = recurses valueCycle.combined.services.east;
  testValueCycleValidation = recurses valueCycle.validate;
}
