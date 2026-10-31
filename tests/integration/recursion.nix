# Strict collection reads and cyclic values recurse through static shared
# reads.
{
  fixtures,
  helpers,
  lib,
  ...
}:
let
  staticStrict = (helpers.mkStaticCollectionConsumer lib.types.attrsOf).lib.registry;
  staticValueCycle =
    (helpers.mkStaticConsumer {
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
            ({ registry, ... }: {
              registry.services.${name} = registry.combined.services.${peer};
            })
          ])
          {
            east = "west";
            west = "east";
          };
    }).lib.registry;
  staticImportCycle =
    (helpers.mkStaticConsumer {
      schemaModules = [ fixtures.schemas.service ];
      centralModules = [ { domain = "example.test"; } ];
      nodeModules.publisher = [
        # The registry argument comes from configuration, so imports cannot
        # depend on it; `specialArgs` supplies it to import selection.
        ({ registry, ... }: {
          imports = lib.optional (registry.central.domain == "example.test") {
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
  testStrictCollectionCombinedRead = recurses staticStrict.combined.endpoints.domain;
  testStrictCollectionValidation = recurses staticStrict.valid;
  testValueCycleCombinedRead = recurses staticValueCycle.combined.services.east;
  testValueCycleValidation = recurses staticValueCycle.valid;
  testImportCycleValidation = recurses staticImportCycle.valid;
}
