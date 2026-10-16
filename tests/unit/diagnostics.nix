# Diagnostics of generated nodes name the option path, node, and available
# source files. Each regex lists those facts in message order.
{
  fixtures,
  helpers,
  lib,
  registryLib,
  ...
}:
let
  inherit (registryLib) mkRegistry;
  inherit (helpers.diagnostics) fails rootCases validateNodeModules;
  serviceSchema = ../../examples/plain-nix/service-schema.nix;

  mkGeneratedNode =
    _settings: registry: modules:
    lib.evalModules {
      modules = [ registry.module ] ++ modules;
    };

  validate = validateNodeModules mkGeneratedNode;
in
rootCases validate
// {
  testInvalidPort =
    fails
      (validate {
        "service publisher" = [ fixtures.invalidService ];
      })
      "`services\\.api\\.port' is not of type[\\s\\S]*`node service publisher: [^']*/invalid-service\\.nix'";

  testDefinitionOrigin =
    fails
      (validate {
        "generated service publisher" = [
          {
            registry.services.api = {
              host = "api.example.test";
              port = lib.mkDefinition {
                file = "/generated/service-port.nix";
                value = lib.mkOverride 70 "invalid port";
              };
            };
          }
        ];
      })
      "`services\\.api\\.port' is not of type[\\s\\S]*`node generated service publisher: /generated/service-port\\.nix'";

  testSubmoduleOrigin =
    fails
      (validate {
        "imported service publisher" = [
          { registry.services.api = fixtures.invalidServiceRecord; }
        ];
      })
      "`services\\.api\\.port' is not of type[\\s\\S]*`node imported service publisher: [^']*/invalid-service-record\\.nix'";

  testModuleOrigin =
    fails
      (validate {
        "module service publisher" = [
          {
            registry.services.api = _: {
              _file = "/modules/service-record.nix";
              host = "api.example.test";
              port = "invalid port";
            };
          }
        ];
      })
      "`services\\.api\\.port' is not of type[\\s\\S]*`node module service publisher: /modules/service-record\\.nix'";

  testMissingRequired = fails (validate {
    "incomplete service publisher" = [
      { registry.services.api.host = "api.example.test"; }
    ];
  }) "`services\\.api\\.port' was accessed but has no value defined";

  testUnknownOption =
    fails
      (validate {
        "unknown service publisher" = [
          {
            _file = "/modules/unknown-service.nix";
            registry.services.api = {
              host = "api.example.test";
              port = 443;
              undeclared = true;
            };
          }
        ];
      })
      "`services\\.api\\.undeclared' does not exist[\\s\\S]*`node unknown service publisher: /modules/unknown-service\\.nix'";

  testReadOnly =
    fails
      (validate {
        "endpoint publisher" = [
          {
            _file = "/modules/endpoint.nix";
            registry.services.api = {
              host = "api.example.test";
              port = 443;
              endpoint = "replacement.example.test:443";
            };
          }
        ];
      })
      "`services\\.api\\.endpoint' is read-only[\\s\\S]*`node endpoint publisher: /modules/endpoint\\.nix'";

  testPriorityConflict =
    fails
      (validate {
        "first address publisher" = [
          {
            _file = "/modules/first-address.nix";
            registry = lib.mkOverride 60 (
              lib.mkMerge [
                { services.api.host = "first.example.test"; }
                { services.api.port = 443; }
              ]
            );
          }
        ];
        "second address publisher" = [
          {
            _file = "/modules/second-address.nix";
            registry = lib.mkOverride 60 {
              domain = "example.test";
              services.api.host = "second.example.test";
            };
          }
        ];
      })
      "`services\\.api\\.host' has conflicting definition values[\\s\\S]*`node first address publisher: /modules/first-address\\.nix'[\\s\\S]*`node second address publisher: /modules/second-address\\.nix'";

  testSchemaDeclaration =
    fails
      (validate {
        "schema-changing publisher" = [
          {
            _file = "/modules/schema-contribution.nix";
            registry.services.api = _: {
              options.injected = lib.mkOption {
                type = lib.types.str;
                default = "undeclared shared option";
                description = "An option absent from the caller's schema.";
              };
            };
          }
        ];
      })
      "`registry\\.services\\.api` from node `schema-changing publisher` in `/modules/schema-contribution\\.nix` declares options; use schemaModules";

  testImportedSchemaDeclaration =
    fails
      (validate {
        "importing schema publisher" = [
          {
            _file = "/modules/importing-contribution.nix";
            registry.services.api = fixtures.sharedSchemaData;
          }
        ];
      })
      "`registry\\.services\\.api` from node `importing schema publisher` in `[^`]*/shared-schema-data\\.nix` declares options; use schemaModules";

  testDefinitionSchemaDeclaration =
    fails
      (validate {
        "generated schema publisher" = [
          {
            _file = "/modules/generated-contribution.nix";
            registry.services = lib.mkDefinition {
              file = "/generated/offending-contribution.nix";
              value.api = _: {
                options.injected = lib.mkOption {
                  type = lib.types.str;
                  default = "undeclared shared option";
                  description = "An option absent from the caller's schema.";
                };
              };
            };
          }
        ];
      })
      "`registry\\.services\\.api` from node `generated schema publisher` in `/generated/offending-contribution\\.nix` declares options; use schemaModules";

  testMissingOption =
    fails
      (mkRegistry {
        inherit lib;
        schemaModules = [ serviceSchema ];
        centralModules = [ { domain = "example.test"; } ];
        nodes."missing contribution interface" = lib.evalModules {
          modules = [ ];
        };
      }).validate
      "node `missing contribution interface` is missing options\\.registry; import registry\\.module";

  testIncompatibleOption =
    fails
      (mkRegistry {
        inherit lib;
        schemaModules = [ serviceSchema ];
        centralModules = [ { domain = "example.test"; } ];
        nodes."unrelated registry option" = lib.evalModules {
          modules = [
            {
              options.registry = lib.mkOption {
                type = lib.types.str;
                default = "unrelated data";
                description = "An incompatible contribution interface.";
              };
            }
          ];
        };
      }).validate
      "node `unrelated registry option` has an incompatible options\\.registry; import registry\\.module";

  testUnrelatedSubmodule =
    fails
      (mkRegistry {
        inherit lib;
        schemaModules = [ serviceSchema ];
        centralModules = [ { domain = "example.test"; } ];
        nodes."handwritten contribution root" = lib.evalModules {
          modules = [
            {
              options.registry = lib.mkOption {
                type = lib.types.submodule {
                  options.domain = lib.mkOption {
                    type = lib.types.str;
                    description = "An independently declared domain.";
                  };
                };
                default = { };
                description = "A root declared without the generated module.";
              };
            }
          ];
        };
      }).validate
      "node `handwritten contribution root` has an incompatible options\\.registry; import registry\\.module";

  # A native module-system error; the node name stays in the trace context.
  testConflictingInterface =
    fails
      (validateNodeModules mkGeneratedNode {
        "conflicting contribution interface" = [
          {
            _file = "/modules/conflicting-interface.nix";
            # A type extension must not repeat the generated option's
            # description.
            options.registry = lib.mkOption { type = lib.types.str; };
          }
        ];
      })
      "`registry' in `[^']*/lib/mk-registry\\.nix' is already declared in `/modules/conflicting-interface\\.nix'";
}
