# Strict collection reads and cyclic values recurse through the constructor
# and through static shared reads.
{
  exports,
  flakeParts,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;
  inherit (exports.lib) mkRegistry;
  collectionLaziness = import ../examples/plain-nix/collection-laziness.nix {
    inherit lib mkRegistry;
  };
  valueCycle = import ../examples/plain-nix/value-cycle.nix { inherit lib mkRegistry; };
  mkConsumer = import ./fixtures/static-flake-consumer.nix {
    inherit flakeParts nixpkgs system;
  };
  staticStrict =
    (import ./fixtures/static-collection-consumer.nix {
      inherit flakeParts nixpkgs system;
    } lib.types.attrsOf).lib.registry;
  staticValueCycle =
    (mkConsumer {
      schemaModules = [
        {
          options.services = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.str;
            default = { };
            description = "Named service endpoints.";
          };
        }
      ];
      nodeModules =
        lib.mapAttrs
          (name: peer: [
            ({ config, ... }: {
              registry.services.${name} = config.registry.combined.services.${peer};
            })
          ])
          {
            east = "west";
            west = "east";
          };
    }).lib.registry;
  staticImportCycle =
    (mkConsumer {
      schemaModules = [ ../examples/plain-nix/service-schema.nix ];
      centralModules = [ { domain = "example.test"; } ];
      nodeModules.publisher = [
        ({ config, ... }: {
          imports = lib.optional (config.registry.central.domain == "example.test") {
            registry.services.api = {
              host = "api.example.test";
              port = 8443;
            };
          };
        })
      ];
    }).lib.registry;
  recurses = expr: {
    inherit expr;
    expectedError = {
      type = "EvalError";
      msg = "infinite recursion encountered";
    };
  };
in
{
  constructor = {
    testStrictCollectionCombinedRead = recurses collectionLaziness.strict.combined.settings.domain;
    testStrictCollectionValidation = recurses collectionLaziness.strict.validate;
    testValueCycleCombinedRead = recurses valueCycle.combined.services.east;
    testValueCycleValidation = recurses valueCycle.validate;
  };
  static = {
    testStrictCollectionCombinedRead = recurses staticStrict.combined.endpoints.domain;
    testStrictCollectionValidation = recurses staticStrict.validate;
    testValueCycleCombinedRead = recurses staticValueCycle.combined.services.east;
    testValueCycleValidation = recurses staticValueCycle.validate;
    testImportCycleValidation = recurses staticImportCycle.validate;
  };
}
