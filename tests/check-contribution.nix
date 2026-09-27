{
  lib,
  mkRegistry,
  mkNode ?
    { registry, contribution, ... }:
    lib.evalModules {
      modules = [
        registry.module
        { registry = contribution; }
      ];
    },
}:
let
  entryType = lib.types.submodule {
    options.endpoint = lib.mkOption {
      type = lib.types.str;
      description = "Service endpoint.";
    };
  };
  shapes = {
    attributes = {
      type = lib.types.lazyAttrsOf entryType;
      wrap = value: { backup = value; };
    };
    list = {
      type = lib.types.listOf entryType;
      wrap = value: [ value ];
    };
    nullable = {
      type = lib.types.nullOr entryType;
      wrap = lib.id;
    };
    unique = {
      type = lib.types.uniq entryType;
      wrap = lib.id;
    };
    union = {
      type = lib.types.either lib.types.str entryType;
      wrap = lib.id;
    };
    coercion = {
      type = lib.types.coercedTo lib.types.str (endpoint: { inherit endpoint; }) entryType;
      wrap = lib.id;
    };
    tagged = {
      type = lib.types.attrTag {
        entry = lib.mkOption {
          type = entryType;
          description = "Service entry.";
        };
      };
      wrap = value: { entry = value; };
    };
    freeform = {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf entryType;
      };
      wrap = value: { backup = value; };
    };
  };

  mkContributionRegistry =
    shape: contribution:
    let
      schemaModules = [
        {
          options.service = lib.mkOption {
            inherit (shape) type;
            description = "Shared service data.";
          };
        }
      ];
      registry = mkRegistry {
        inherit lib schemaModules;
        nodes.publisher = mkNode {
          inherit registry schemaModules;
          contribution.service = shape.wrap contribution;
        };
      };
    in
    registry;
in
{
  testContributionsCannotDisableSchemaModules = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submodule [ ./fixtures/required-endpoint.nix ];
              wrap = lib.id;
            }
            (_: {
              disabledModules = [ ./fixtures/required-endpoint.nix ];
            });
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testContributionsCanDisableContributionModules = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submodule {
                options.endpoints = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Service endpoints.";
                };
              };
              wrap = lib.id;
            }
            (_: {
              imports = [ ./fixtures/service-endpoints.nix ];
              disabledModules = [ ./fixtures/service-endpoints.nix ];
              endpoints = [ "active.example.test:443" ];
            });
      in
      {
        endpoints = registry.combined.service.endpoints;
        inherit (registry) validate;
      };
    expected = {
      endpoints = [ "active.example.test:443" ];
      validate = true;
    };
  };

  testDisablesContributionModulesByRelativePath = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submoduleWith {
                specialArgs.modulesPath = ./fixtures;
                modules = [
                  {
                    options.endpoints = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      description = "Service endpoints.";
                    };
                  }
                ];
              };
              wrap = lib.id;
            }
            {
              imports = [ ./fixtures/service-endpoints.nix ];
              disabledModules = [ "service-endpoints.nix" ];
              config.endpoints = [ "active.example.test:443" ];
            };
      in
      {
        endpoints = registry.combined.service.endpoints;
        inherit (registry) validate;
      };
    expected = {
      endpoints = [ "active.example.test:443" ];
      validate = true;
    };
  };

  testRejectsDisablingSchemaModulesByRelativePath = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submoduleWith {
                specialArgs.modulesPath = ./fixtures;
                modules = [ ./fixtures/required-endpoint.nix ];
              };
              wrap = lib.id;
            }
            {
              disabledModules = [ "required-endpoint.nix" ];
            };
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testContributionsCannotDisableImportedSchemaModules = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submodule {
                imports = [ ./fixtures/required-endpoint.nix ];
              };
              wrap = lib.id;
            }
            (_: {
              disabledModules = [ ./fixtures/required-endpoint.nix ];
            });
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testRejectsDisablingSchemaModulesByOptionPath = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submodule (
                { _prefix, ... }:
                {
                  key = lib.showOption _prefix;
                  imports = [ ./fixtures/required-endpoint.nix ];
                }
              );
              wrap = lib.id;
            }
            (
              { _prefix, ... }: {
                disabledModules = [ { key = lib.showOption _prefix; } ];
              }
            );
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testContributionModuleSyntaxCannotExtendTheSchema = {
    expr =
      let
        openRegistry =
          mkContributionRegistry
            {
              type = entryType;
              wrap = lib.id;
            }
            (_: {
              freeformType = lib.types.attrsOf lib.types.anything;
              endpoint = "backup.example.test:443";
              injected = "undeclared data";
            });
        metaShape = {
          type = lib.types.submodule {
            options.meta = lib.mkOption {
              type = entryType;
              description = "Service metadata.";
            };
          };
          wrap = lib.id;
        };
        metaRegistry = mkContributionRegistry metaShape (_: {
          config = { };
          meta =
            { lib, ... }:
            {
              options.injected = lib.mkOption {
                type = lib.types.str;
                default = "node-owned schema";
                description = "An option absent from schemaModules.";
              };
              config.endpoint = "backup.example.test:443";
            };
        });
        validMetaRegistry = mkContributionRegistry metaShape (_: {
          config = { };
          meta.endpoint = "backup.example.test:443";
        });
      in
      {
        freeform = (builtins.tryEval openRegistry.validate).success;
        meta = (builtins.tryEval metaRegistry.validate).success;
        metaEndpoint = validMetaRegistry.combined.service.meta.endpoint;
      };
    expected = {
      freeform = false;
      meta = false;
      metaEndpoint = "backup.example.test:443";
    };
  };

  testFreeformContributionsPreserveModuleMetadata = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = shapes.freeform.type;
              wrap = lib.id;
            }
            (_: {
              key = "/contribution";
              _file = "/service-contribution.nix";
              _class = null;
              disabledModules = [ ];
              backup.endpoint = "backup.example.test:443";
            });
      in
      registry.combined.service;
    expected.backup.endpoint = "backup.example.test:443";
  };

  testLegacyContributionImportsCannotDeclareOptions = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = entryType;
              wrap = lib.id;
            }
            (_: {
              require = [
                (
                  { lib, ... }:
                  {
                    options.injected = lib.mkOption {
                      type = lib.types.str;
                      default = "node-owned schema";
                      description = "An option absent from schemaModules.";
                    };
                    config.endpoint = "backup.example.test:443";
                  }
                )
              ];
            });
      in
      (builtins.tryEval registry.validate).success;
    expected = false;
  };

  testFunctionsCannotDeclareResultOptions = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.functionTo entryType;
              wrap = lib.id;
            }
            (
              endpoint:
              { lib, ... }:
              {
                options.injected = lib.mkOption {
                  type = lib.types.str;
                  default = "node-owned schema";
                  description = "An option absent from schemaModules.";
                };
                config = { inherit endpoint; };
              }
            );
      in
      (builtins.tryEval (builtins.deepSeq (registry.combined.service "backup.example.test:443") true))
      .success;
    expected = false;
  };

  testFunctionsKeepTheirDataAndArguments = {
    expr =
      let
        registry = mkContributionRegistry {
          type = lib.types.functionTo entryType;
          wrap = lib.id;
        } ({ endpoint }: _: { inherit endpoint; });
      in
      {
        arguments = lib.functionArgs registry.combined.service;
        data = registry.combined.service { endpoint = "backup.example.test:443"; };
      };
    expected = {
      arguments.endpoint = false;
      data.endpoint = "backup.example.test:443";
    };
  };

  testFileContributionsRetainModuleSemantics = {
    expr =
      let
        registry = mkContributionRegistry {
          type = lib.types.submodule {
            options.endpoints = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Service endpoints.";
            };
          };
          wrap = lib.id;
        } ./fixtures/service-endpoints.nix;
      in
      registry.combined.service.endpoints;
    expected = [ "backup.example.test:443" ];
  };

  testRepeatedContributionImportsRetainModuleIdentity = {
    expr =
      let
        registry =
          mkContributionRegistry
            {
              type = lib.types.submodule {
                options.endpoints = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Service endpoints.";
                };
              };
              wrap = lib.id;
            }
            (_: {
              imports = [
                ./fixtures/service-endpoints.nix
                ./fixtures/service-endpoints.nix
              ];
            });
      in
      registry.combined.service.endpoints;
    expected = [ "backup.example.test:443" ];
  };

  testInvalidSubmoduleValuesRetainTypeFailures = {
    expr =
      (builtins.tryEval
        (mkContributionRegistry {
          type = entryType;
          wrap = lib.id;
        } "not a module").validate
      ).success;
    expected = false;
  };

  testCollectionTypesKeepDataOnlySubmoduleFunctions = {
    expr = builtins.mapAttrs (
      _: shape:
      let
        registry = mkContributionRegistry shape (_: {
          imports = [ { endpoint = "backup.example.test:443"; } ];
        });
      in
      registry.validate
      && registry.combined.service == shape.wrap { endpoint = "backup.example.test:443"; }
    ) shapes;
    expected = {
      attributes = true;
      list = true;
      nullable = true;
      unique = true;
      union = true;
      coercion = true;
      tagged = true;
      freeform = true;
    };
  };

  testCollectionsRejectContributionSchemaExtensions = {
    expr = builtins.mapAttrs (
      _: shape:
      let
        registry = mkContributionRegistry shape (
          { lib, ... }:
          {
            options.injected = lib.mkOption {
              type = lib.types.str;
              default = "node-owned schema";
              description = "An option absent from schemaModules.";
            };
            config.endpoint = "backup.example.test:443";
          }
        );
      in
      (builtins.tryEval registry.validate).success
    ) shapes;
    expected = {
      attributes = false;
      list = false;
      nullable = false;
      unique = false;
      union = false;
      coercion = false;
      tagged = false;
      freeform = false;
    };
  };
}
