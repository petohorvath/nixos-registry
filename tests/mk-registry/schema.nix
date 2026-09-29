{ lib, mkRegistry }:
let
  schema = {
    options.domain = lib.mkOption {
      type = lib.types.str;
      description = "Domain used by shared services.";
    };
  };

  serviceSchema = {
    options.services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          config._module.args.port = 443;
          options.endpoint = lib.mkOption {
            type = lib.types.str;
            description = "Service endpoint.";
          };
        }
      );
      default = { };
      description = "Named services.";
    };
  };
in
{
  testCentralKeysDoNotForceCentralDefinitions = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = throw "Central definitions were forced.";
          nodes = throw "Node collection was forced.";
        };
      in
      builtins.attrNames registry.central;
    expected = [ "domain" ];
  };

  testCentralReadsDoNotCollectNodes = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [ { domain = "example.test"; } ];
          nodes = throw "Node collection was forced.";
        };
      in
      registry.central.domain;
    expected = "example.test";
  };

  testReadsDoNotForceInvalidNodeContributions = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [ { domain = "example.test"; } ];
          nodes.publisher = lib.evalModules {
            modules = [
              registry.module
              { registry = throw "Node contribution was forced."; }
            ];
          };
        };
      in
      {
        centralKeys = builtins.attrNames registry.central;
        combinedKeys = builtins.attrNames registry.combined;
        centralDomain = registry.central.domain;
        combinedReadSucceeds = (builtins.tryEval registry.combined.domain).success;
      };
    expected = {
      centralKeys = [ "domain" ];
      combinedKeys = [ "domain" ];
      centralDomain = "example.test";
      combinedReadSucceeds = false;
    };
  };

  testCombinedKeysDoNotCollectNodes = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes = throw "Node collection was forced.";
        };
      in
      builtins.attrNames registry.combined;
    expected = [ "domain" ];
  };

  testNodesSelectModulesUsingDeclaredKeysAndCentralData = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [
            schema
            (
              { collectionName, ... }:
              {
                options.${collectionName} = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Named service endpoints.";
                };
              }
            )
          ];
          centralModules = [ ({ centralDomain, ... }: { domain = centralDomain; }) ];
          specialArgs = {
            centralDomain = "example.test";
            collectionName = "services";
          };
          nodes.publisher = lib.evalModules {
            specialArgs = { inherit registry; };
            modules = [
              registry.module
              (
                { registry, ... }:
                {
                  imports = lib.optionals (
                    builtins.attrNames registry.central == [
                      "domain"
                      "services"
                    ]
                    &&
                      builtins.attrNames registry.combined == [
                        "domain"
                        "services"
                      ]
                    && registry.central.domain == "example.test"
                  ) [ { registry.services.backup = "backup.example.test:443"; } ];
                }
              )
            ];
          };
        };
      in
      registry.combined.services;
    expected.backup = "backup.example.test:443";
  };

  testRejectsFreeformSchemaRoots = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [
            schema
            { freeformType = lib.types.attrsOf lib.types.anything; }
          ];
          centralModules = [ { domain = "example.test"; } ];
          nodes = { };
        };
      in
      registry.validate;
    expectedError.msg = "unrestricted freeform roots are unsupported";
  };

  testCentralModulesCannotOpenTheRegistryRoot = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [
            {
              freeformType = lib.types.attrsOf lib.types.anything;
              domain = "example.test";
            }
          ];
          nodes = { };
        };
      in
      registry.validate;
    expectedError.msg = "unrestricted freeform roots are unsupported";
  };

  testContributionsCannotOpenTheRegistryRoot = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes.publisher = lib.evalModules {
            modules = [
              registry.module
              {
                registry = {
                  _module.freeformType = lib.types.attrsOf lib.types.anything;
                  domain = "example.test";
                  injected = "undeclared data";
                };
              }
            ];
          };
        };
      in
      registry.validate;
    expectedError.msg = "contribution at `registry` from node `publisher` in `[^`]*` changes module controls";
  };

  testNodeOptionDeclarationsDoNotExtendTheSharedSchema = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes.publisher = lib.evalModules {
            modules = [
              registry.module
              {
                options.registry = lib.mkOption {
                  type = lib.types.submodule {
                    options.injected = lib.mkOption {
                      type = lib.types.str;
                      description = "A node-local option.";
                    };
                  };
                  description = "A node-local registry extension.";
                };
                config.registry = {
                  domain = "example.test";
                  injected = "undeclared shared data";
                };
              }
            ];
          };
        };
      in
      {
        keys = builtins.attrNames registry.combined;
        valid = (builtins.tryEval registry.validate).success;
      };
    expected = {
      keys = [ "domain" ];
      valid = false;
    };
  };

  testContributionsCannotDeclareCollectionEntryOptions = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ serviceSchema ];
          nodes.publisher = lib.evalModules {
            modules = [
              registry.module
              {
                registry.services.backup =
                  { lib, ... }:
                  {
                    options.injected = lib.mkOption {
                      type = lib.types.str;
                      default = "node-owned schema";
                      description = "An option absent from schemaModules.";
                    };
                    config.endpoint = "backup.example.test:443";
                  };
              }
            ];
          };
        };
      in
      registry.validate;
    expectedError.msg = "contribution at `registry\\.services\\.backup` from node `publisher` in `[^`]*` declares options";
  };

  testDataOnlySubmoduleFunctionsKeepTheirArguments = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ serviceSchema ];
          nodes.publisher = lib.evalModules {
            modules = [
              registry.module
              {
                registry.services.backup =
                  { name, port, ... }:
                  {
                    endpoint = "${name}.example.test:${toString port}";
                  };
              }
            ];
          };
        };
      in
      registry.combined.services.backup.endpoint;
    expected = "backup.example.test:443";
  };

  testConstructorKeepsSchemaNamesReservedByStaticModules = {
    expr =
      let
        legacy = mkRegistry {
          inherit lib;
          schemaModules = [
            {
              options = lib.genAttrs [ "settings" "central" "combined" "validate" ] (
                name:
                lib.mkOption {
                  type = lib.types.str;
                  description = "Schema-owned ${name} through the constructor.";
                }
              );
            }
          ];
          nodes.generic = lib.evalModules {
            modules = [
              legacy.module
              {
                registry = {
                  settings = "local settings";
                  central = "local central";
                  combined = "local combined";
                  validate = "local validate";
                };
              }
            ];
          };
        };
      in
      {
        inherit (legacy) combined validate;
      };
    expected = {
      combined = {
        settings = "local settings";
        central = "local central";
        combined = "local combined";
        validate = "local validate";
      };
      validate = true;
    };
  };
}
