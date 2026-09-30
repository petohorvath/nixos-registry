# Diagnostics name the option path, node, and available source files. Each
# regex lists those facts in message order.
{
  exports,
  flakeParts,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;
  inherit (exports.lib) mkRegistry;
  serviceSchema = ../examples/plain-nix/service-schema.nix;

  mkProjectRegistry =
    modules:
    (flakeParts.lib.mkFlake { inputs.self.outPath = ../.; } (
      { config, ... }: {
        imports = [ exports.flakeModules.default ] ++ modules;
        systems = [ ];
        flake.lib.registry = config.registry;
      }
    )).lib.registry;

  mkRegistryWithDuplicateSettings =
    settings:
    mkProjectRegistry [
      {
        _file = "/modules/first-project.nix";
        registry.settings = settings;
      }
      {
        _file = "/modules/second-project.nix";
        registry.settings = settings;
      }
    ];

  mkStaticNode =
    settings: registry: modules:
    nixpkgs.lib.nixosSystem {
      modules = [
        exports.nixosModules.default
        {
          nixpkgs.hostPlatform = system;
          registry = {
            inherit settings;
            inherit (registry) central combined validate;
          };
        }
      ]
      ++ modules;
    };

  fails = expr: msg: {
    inherit expr;
    expectedError.msg = msg;
  };

  mkGeneratedNode =
    _settings: registry: modules:
    lib.evalModules {
      modules = [ registry.module ] ++ modules;
    };

  validateNodeModules =
    mkNode: nodeModules:
    let
      settings.schemaModules = [
        serviceSchema
        {
          options.backupPaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Ordered backup paths.";
          };
        }
      ];
      registry = mkRegistry {
        inherit lib;
        inherit (settings) schemaModules;
        centralModules = [ { domain = "example.test"; } ];
        nodes = lib.mapAttrs (_: mkNode settings registry) nodeModules;
      };
    in
    registry.validate;

  # Contributions at the `registry` root, which static nodes also receive.
  rootCases = validate: {
    testOrderedList =
      fails
        (validate {
          "ordered path publisher" = [
            {
              _file = "/modules/ordered-paths.nix";
              registry = lib.mkMerge [
                { backupPaths = lib.mkBefore [ 42 ]; }
                { backupPaths = lib.mkAfter [ "/srv/documents" ]; }
              ];
            }
          ];
        })
        "`backupPaths\\.\"\\[definition 1-entry 1\\]\"' is not of type[\\s\\S]*`node ordered path publisher: /modules/ordered-paths\\.nix'";

    testModuleControls =
      fails
        (validate {
          "module-control publisher" = [
            {
              _file = "/modules/contribution-controls.nix";
              registry._module.check = false;
            }
          ];
        })
        "`registry` from node `module-control publisher` in `/modules/contribution-controls\\.nix` changes module controls";
  };

  contributionCases =
    let
      validate = validateNodeModules mkGeneratedNode;
    in
    rootCases validate
    // {
      testInvalidPort =
        fails
          (validate {
            "service publisher" = [ ./fixtures/invalid-service.nix ];
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
              { registry.services.api = ./fixtures/invalid-service-record.nix; }
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
                registry.services.api = ./fixtures/shared-schema-data.nix;
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
    };

  staticInvalidPort =
    let
      settings.schemaModules = [ serviceSchema ];
      registry = mkRegistry (
        settings
        // {
          inherit lib;
          centralModules = [ { domain = "example.test"; } ];
          nodes."static service publisher" = mkStaticNode settings registry [
            ./fixtures/invalid-service.nix
          ];
        }
      );
    in
    {
      shared = registry.validate;
      local =
        (mkStaticNode settings registry [ ./fixtures/invalid-service.nix ])
        .config.registry.services.api.port;
    };
in
{
  generated = contributionCases // {
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
  };

  static = rootCases (validateNodeModules mkStaticNode) // {
    testSharedInvalidPort = fails staticInvalidPort.shared "`services\\.api\\.port' is not of type[\\s\\S]*`node static service publisher: [^']*/invalid-service\\.nix'";

    testLocalInvalidPort = fails staticInvalidPort.local "`registry\\.services\\.api\\.port' is not of type[\\s\\S]*`[^']*/invalid-service\\.nix'";

    testFlakeCheckInvalidPort =
      fails
        ((import ./fixtures/static-flake-consumer.nix { inherit flakeParts nixpkgs system; }) {
          schemaModules = [ serviceSchema ];
          centralModules = [ { domain = "example.test"; } ];
          nodeModules."static service publisher" = [ ./fixtures/invalid-service.nix ];
        }).checks.${system}.registry.drvPath
        "`services\\.api\\.port' is not of type[\\s\\S]*`node static service publisher: [^']*/invalid-service\\.nix'";
  };

  flake = {
    testMissingSchema =
      fails
        (mkProjectRegistry [
          {
            registry.settings.nodes = { };
          }
        ]).validate
        "registry\\.settings\\.schemaModules must be set explicitly";

    testMissingNodes =
      fails
        (mkProjectRegistry [
          {
            registry.settings.schemaModules = [ ];
          }
        ]).validate
        "registry\\.settings\\.nodes must be set explicitly";

    testDuplicateNode =
      fails
        (mkRegistryWithDuplicateSettings {
          schemaModules = [ ];
          nodes."duplicate node" = { };
        }).validate
        "`registry\\.settings\\.nodes\\.\"duplicate node\"' is defined multiple times[\\s\\S]*second-project\\.nix[\\s\\S]*first-project\\.nix";

    testCentralConflict =
      fails
        (mkProjectRegistry [
          {
            _file = "/modules/first-project.nix";
            registry.settings = {
              schemaModules = [ serviceSchema ];
              nodes = { };
              centralModules = [ { domain = "first.example.test"; } ];
            };
          }
          {
            _file = "/modules/second-project.nix";
            registry.settings.centralModules = [ { domain = "second.example.test"; } ];
          }
        ]).validate
        "`domain' has conflicting definition values[\\s\\S]*first-project\\.nix[\\s\\S]*second-project\\.nix";
  };
}
