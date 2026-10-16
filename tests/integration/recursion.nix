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
    (helpers.mkStaticConsumer {
      schemaModules = [ fixtures.schemas.service ];
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
  testStrictCollectionCombinedRead = recurses staticStrict.combined.endpoints.domain;
  testStrictCollectionValidation = recurses staticStrict.validate;
  testValueCycleCombinedRead = recurses staticValueCycle.combined.services.east;
  testValueCycleValidation = recurses staticValueCycle.validate;
  testImportCycleValidation = recurses staticImportCycle.validate;
}
