{ lib, mkRegistry }:
let
  schema = {
    options.domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        Domain used by published services.
      '';
    };
  };

  serviceSchema = {
    options.services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          config._module.args.port = 443;
          options.endpoint = lib.mkOption {
            type = lib.types.str;
            description = ''
              Service endpoint.
            '';
          };
        }
      );
      default = { };
      description = ''
        Named services.
      '';
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

  testViewsDoNotForceInvalidNodeContributions = {
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
                  description = ''
                    Named service endpoints.
                  '';
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
      (builtins.tryEval registry.validate).success;
    expected = false;
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
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testPublicationsCannotOpenTheRegistryRoot = {
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
      (builtins.tryEval registry.validate).success;
    expected = false;
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
                      description = ''
                        A node-local option.
                      '';
                    };
                  };
                  description = ''
                    A node-local registry extension.
                  '';
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

  testPublicationsCannotDeclareCollectionEntryOptions = {
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
                      description = ''
                        An option absent from schemaModules.
                      '';
                    };
                    config.endpoint = "backup.example.test:443";
                  };
              }
            ];
          };
        };
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
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
}
