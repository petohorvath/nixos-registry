{ nixpkgs, system }:
let
  inherit (nixpkgs) lib;
  registryFlake = import ../helpers/plain-exports.nix;
  schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
  registry = registryFlake.lib.mkRegistry {
    inherit lib schemaModules;
    centralModules = [ { domain = "example.test"; } ];
    nodes."metrics publisher" = node;
  };
  node = lib.nixosSystem {
    modules = [
      registryFlake.nixosModules.default
      {
        registry = {
          settings = { inherit schemaModules; };
          inherit (registry) central combined validate;
        };
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
        services.prometheus.port = 9191;
      }
      ({ config, ... }: {
        registry.services.metrics = {
          host = "monitor.${config.registry.central.domain}";
          port = config.services.prometheus.port;
        };
        environment.etc."metrics-endpoint".text = config.registry.combined.services.metrics.endpoint;
      })
    ];
  };
in
{
  testStaticNixosModuleRejectsUnknownSettings = {
    expr =
      (builtins.tryEval
        (node.extendModules {
          modules = [ { registry.settings.unknown = true; } ];
        }).config.registry.settings
      ).success;
    expected = false;
  };

  testStaticNixosExampleEvaluatesAndValidates = {
    expr = (import ../../examples/static-nixos { inherit nixpkgs system; }).result;
    expected = {
      central = {
        domain = "example.test";
        services = { };
      };
      combined = {
        domain = "example.test";
        services.metrics = {
          host = "monitor.example.test";
          port = 9191;
          endpoint = "monitor.example.test:9191";
        };
      };
      endpoint = "monitor.example.test:9191";
      validate = true;
    };
  };

  testStaticNixosModuleUsesCallerSchemaAndSeparateArguments = {
    expr =
      let
        selectedLib = lib.extend (_final: _previous: { registryPortType = lib.types.port; });
        settings = {
          schemaModules = [
            ({ lib, schemaLabel, ... }: {
              options = {
                schemaModules = lib.mkOption {
                  type = lib.types.str;
                  default = schemaLabel;
                  description = ''
                    A schema-owned field beside the settings group.
                  '';
                };
                port = lib.mkOption {
                  type = lib.registryPortType;
                  description = ''
                    A port checked with the consumer's extended library.
                  '';
                };
              };
            })
          ];
          specialArgs = {
            schemaLabel = "shared schema";
            nodePort = 1111;
          };
        };
        shared = registryFlake.lib.mkRegistry (
          settings
          // {
            lib = selectedLib;
            nodes."argument owner" = configured;
          }
        );
        configured = selectedLib.nixosSystem {
          specialArgs.nodePort = 2222;
          modules = [
            registryFlake.nixosModules.default
            {
              nixpkgs.hostPlatform = system;
              registry = {
                inherit settings;
                inherit (shared) central combined validate;
              };
            }
            ({ nodePort, ... }: {
              registry = {
                port = nodePort;
                schemaModules = "node schema label";
              };
            })
          ];
        };
      in
      {
        localLabel = configured.config.registry.schemaModules;
        centralLabel = configured.config.registry.central.schemaModules;
        localPort = configured.config.registry.port;
        inherit (configured.config.registry) combined validate;
      };
    expected = {
      localLabel = "node schema label";
      centralLabel = "shared schema";
      localPort = 2222;
      combined = {
        schemaModules = "node schema label";
        port = 2222;
      };
      validate = true;
    };
  };

  testStaticNixosModuleRejectsReservedSchemaNames = {
    expr =
      map
        (
          name:
          let
            collisionSchema = [
              {
                options.${name} = lib.mkOption {
                  type = lib.types.str;
                  default = "schema-owned value";
                  description = ''
                    A field that collides with the static interface.
                  '';
                };
              }
            ];
            collisionRegistry = registryFlake.lib.mkRegistry {
              inherit lib;
              schemaModules = collisionSchema;
              nodes."colliding node" = collisionNode;
            };
            collisionNode = lib.nixosSystem {
              modules = [
                registryFlake.nixosModules.default
                {
                  nixpkgs.hostPlatform = system;
                  registry.settings.schemaModules = collisionSchema;
                  registry = { inherit (collisionRegistry) central combined validate; };
                }
              ];
            };
          in
          {
            local = (builtins.tryEval collisionNode.config.registry).success;
            shared = (builtins.tryEval collisionRegistry.validate).success;
          }
        )
        [
          "settings"
          "central"
          "combined"
          "validate"
        ];
    expected = lib.replicate 4 {
      local = false;
      shared = false;
    };
  };

  testStaticNixosModuleContributesAndReadsSharedResults = {
    expr = {
      inherit (node.config.registry) central combined validate;
      local = node.config.registry.services.metrics;
      endpoint = node.config.environment.etc."metrics-endpoint".text;
      port = node.config.services.prometheus.port;
    };
    expected = {
      central = {
        domain = "example.test";
        services = { };
      };
      combined = {
        domain = "example.test";
        services.metrics = {
          host = "monitor.example.test";
          port = 9191;
          endpoint = "monitor.example.test:9191";
        };
      };
      local = {
        host = "monitor.example.test";
        port = 9191;
        endpoint = "monitor.example.test:9191";
      };
      endpoint = "monitor.example.test:9191";
      port = 9191;
      validate = true;
    };
  };
}
