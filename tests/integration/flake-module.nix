{
  fixtures,
  helpers,
  lib,
  ...
}:
let
  mkConsumer =
    modules:
    helpers.mkProject { } (
      [
        (
          { config, ... }:
          {
            systems = [ ];
            flake.lib.registry = config.registry;
          }
        )
      ]
      ++ modules
    );
  consumer = mkConsumer [
    (
      { config, ... }:
      let
        commonModule = {
          imports = [ config.registry.module ];
          system.stateVersion = "26.05";
        };
      in
      {
        registry = {
          schemaModules = [ fixtures.schemas.service ];
          centralModules = [
            {
              domain = "example.test";
              backupPaths = lib.mkBefore [ "/srv/primary" ];
            }
          ];
          nodes = {
            "metrics publisher" = config.flake.nixosConfigurations.monitor;
          };
        };
        flake.nixosConfigurations = {
          monitor = helpers.mkNixosNode {
            modules = [
              commonModule
              ({ config, registry, ... }: {
                networking.hostName = "monitor";
                services.prometheus.port = 9191;
                registry.services.metrics = {
                  host = "${config.networking.hostName}.${registry.central.domain}";
                  port = config.services.prometheus.port;
                };
              })
            ];
          };
          backup = helpers.mkNixosNode {
            modules = [
              commonModule
              ({ config, registry, ... }: {
                networking.hostName = "backup";
                registry.services.backup = {
                  host = "${config.networking.hostName}.${registry.central.domain}";
                  port = 8022;
                };
                environment.etc."metrics-endpoint".text = registry.combined.services.metrics.endpoint;
              })
            ];
          };
          unselected = throw "Configurations outside registry.nodes must not be collected.";
        };
      }
    )
    ({ config, lib, ... }: {
      registry = {
        schemaModules = [
          ({ lib, ... }: {
            options.backupPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Shared backup paths.";
            };
          })
        ];
        centralModules = [ { backupPaths = lib.mkAfter [ "/srv/archive" ]; } ];
        nodes."backup reader" = config.flake.nixosConfigurations.backup;
      };
    })
  ];
in
{
  testStaticFlakeModuleUsesConsumerLibraryAndSeparateArguments = {
    expr =
      let
        selectedLib = lib.extend (_final: _previous: { registryPortType = lib.types.port; });
        configured = helpers.mkProject { specialArgs.lib = selectedLib; } [
          (
            { config, ... }:
            let
              shared = config.registry;
              node = helpers.mkNixosNode {
                lib = selectedLib;
                specialArgs.nodePort = 2222;
                modules = [
                  shared.module
                  ({ nodePort, ... }: { registry.port = nodePort; })
                ];
              };
            in
            {
              systems = [ ];
              registry = {
                schemaModules = [
                  ({ lib, schemaLabel, ... }: {
                    options = {
                      schemaModules = lib.mkOption {
                        type = lib.types.str;
                        default = schemaLabel;
                        description = "A schema-owned label.";
                      };
                      port = lib.mkOption {
                        type = lib.registryPortType;
                        description = "The node's port.";
                      };
                      centralPort = lib.mkOption {
                        type = lib.types.port;
                        description = "A port supplied by a central module.";
                      };
                    };
                  })
                ];
                centralModules = [ ({ nodePort, ... }: { centralPort = nodePort; }) ];
                moduleArgs = {
                  schemaLabel = "shared schema";
                  nodePort = 1111;
                };
                nodes."argument owner" = node;
              };
              flake.lib.result = {
                inherit (shared) combined valid;
                localPort = node.config.registry.port;
                localLabel = node.config.registry.schemaModules;
              };
            }
          )
        ];
      in
      configured.lib.result;
    expected = {
      combined = {
        schemaModules = "shared schema";
        port = 2222;
        centralPort = 1111;
      };
      localPort = 2222;
      localLabel = "shared schema";
      valid = true;
    };
  };

  testStaticFlakeDefaultsAllowEmptyNodes = {
    expr =
      let
        empty =
          (mkConsumer [
            {
              registry = {
                schemaModules = [
                  ({ lib, ... }: {
                    options.domain = lib.mkOption {
                      type = lib.types.str;
                      default = "central.example.test";
                      description = "The shared domain.";
                    };
                  })
                ];
                nodes = { };
              };
            }
          ]).lib.registry;
      in
      {
        inherit (empty)
          central
          centralModules
          combined
          moduleArgs
          nodes
          valid
          ;
      };
    expected = {
      central.domain = "central.example.test";
      centralModules = [ ];
      combined.domain = "central.example.test";
      moduleArgs = { };
      nodes = { };
      valid = true;
    };
  };

  testStaticFlakeModuleHasTheRegistryShape = {
    expr = builtins.attrNames consumer.lib.registry;
    expected = [
      "central"
      "centralModules"
      "combined"
      "module"
      "moduleArgs"
      "nodes"
      "schemaModules"
      "valid"
    ];
  };

  testStaticFlakeModuleSharesOneRegistryWithNixosNodes = {
    expr = {
      inherit (consumer.lib.registry) central combined valid;
      endpoint = consumer.nixosConfigurations.backup.config.environment.etc."metrics-endpoint".text;
      localServices = lib.mapAttrs (
        _: node: builtins.attrNames node.config.registry.services
      ) consumer.lib.registry.nodes;
    };
    expected = {
      central = {
        domain = "example.test";
        services = { };
        backupPaths = [
          "/srv/primary"
          "/srv/archive"
        ];
      };
      combined = {
        domain = "example.test";
        backupPaths = [
          "/srv/primary"
          "/srv/archive"
        ];
        services = {
          metrics = {
            host = "monitor.example.test";
            port = 9191;
            endpoint = "monitor.example.test:9191";
          };
          backup = {
            host = "backup.example.test";
            port = 8022;
            endpoint = "backup.example.test:8022";
          };
        };
      };
      valid = true;
      endpoint = "monitor.example.test:9191";
      localServices = {
        "metrics publisher" = [ "metrics" ];
        "backup reader" = [ "backup" ];
      };
    };
  };
}
