{
  nixpkgs,
  flakeParts,
  system,
}:
let
  inherit (nixpkgs) lib;
  registryFlake = import ./helpers/plain-exports.nix;
  mkConsumer =
    modules:
    flakeParts.lib.mkFlake
      {
        inputs = {
          self.outPath = ../.;
          inherit nixpkgs;
        };
      }
      (
        { config, ... }: {
          imports = [ registryFlake.flakeModules.default ] ++ modules;
          systems = [ ];
          flake.lib.registry = config.registry;
        }
      );
  consumer = mkConsumer [
    (
      { config, ... }:
      let
        shared = config.registry;
        commonModule = {
          imports = [ registryFlake.nixosModules.default ];
          nixpkgs.hostPlatform = system;
          system.stateVersion = "26.05";
          registry = {
            settings = { inherit (shared.settings) schemaModules specialArgs; };
            inherit (shared) central combined validate;
          };
        };
      in
      {
        registry.settings = {
          schemaModules = [ ../examples/plain-nix/service-schema.nix ];
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
          monitor = lib.nixosSystem {
            modules = [
              commonModule
              ({ config, ... }: {
                networking.hostName = "monitor";
                services.prometheus.port = 9191;
                registry.services.metrics = {
                  host = "${config.networking.hostName}.${config.registry.central.domain}";
                  port = config.services.prometheus.port;
                };
              })
            ];
          };
          backup = lib.nixosSystem {
            modules = [
              commonModule
              ({ config, ... }: {
                networking.hostName = "backup";
                registry.services.backup = {
                  host = "${config.networking.hostName}.${config.registry.central.domain}";
                  port = 8022;
                };
                environment.etc."metrics-endpoint".text = config.registry.combined.services.metrics.endpoint;
              })
            ];
          };
          unselected = throw "Configurations outside registry.settings.nodes must not be collected.";
        };
      }
    )
    ({ config, lib, ... }: {
      registry.settings = {
        schemaModules = [
          ({ lib, ... }: {
            options.backupPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Shared backup paths.
              '';
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
        configured =
          flakeParts.lib.mkFlake
            {
              inputs = {
                self.outPath = ../.;
                inherit nixpkgs;
              };
              specialArgs.lib = selectedLib;
            }
            (
              { config, ... }:
              let
                shared = config.registry;
                node = selectedLib.nixosSystem {
                  specialArgs.nodePort = 2222;
                  modules = [
                    registryFlake.nixosModules.default
                    {
                      nixpkgs.hostPlatform = system;
                      registry = {
                        settings = { inherit (shared.settings) schemaModules specialArgs; };
                        inherit (shared) central combined validate;
                      };
                    }
                    ({ nodePort, ... }: { registry.port = nodePort; })
                  ];
                };
              in
              {
                imports = [ registryFlake.flakeModules.default ];
                systems = [ ];
                registry.settings = {
                  schemaModules = [
                    ({ lib, schemaLabel, ... }: {
                      options = {
                        schemaModules = lib.mkOption {
                          type = lib.types.str;
                          default = schemaLabel;
                          description = ''
                            A schema-owned label.
                          '';
                        };
                        port = lib.mkOption {
                          type = lib.registryPortType;
                          description = ''
                            The node's port.
                          '';
                        };
                        centralPort = lib.mkOption {
                          type = lib.types.port;
                          description = ''
                            A port supplied by a central module.
                          '';
                        };
                      };
                    })
                  ];
                  centralModules = [ ({ nodePort, ... }: { centralPort = nodePort; }) ];
                  specialArgs = {
                    schemaLabel = "shared schema";
                    nodePort = 1111;
                  };
                  nodes."argument owner" = node;
                };
                flake.lib.result = {
                  inherit (shared) combined validate;
                  localPort = node.config.registry.port;
                  localLabel = node.config.registry.schemaModules;
                };
              }
            );
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
      validate = true;
    };
  };

  testStaticFlakeModuleRequiresSchemaAndNodeSettings = {
    expr =
      map
        (
          name:
          (builtins.tryEval
            (mkConsumer [
              {
                registry.settings = removeAttrs {
                  schemaModules = [ ];
                  nodes = { };
                } [ name ];
              }
            ]).lib.registry.validate
          ).success
        )
        [
          "schemaModules"
          "nodes"
        ];
    expected = [
      false
      false
    ];
  };

  testStaticFlakeDefaultsAllowEmptyNodes = {
    expr =
      let
        empty =
          (mkConsumer [
            {
              registry.settings = {
                schemaModules = [
                  ({ lib, ... }: {
                    options.domain = lib.mkOption {
                      type = lib.types.str;
                      default = "central.example.test";
                      description = ''
                        The shared domain.
                      '';
                    };
                  })
                ];
                nodes = { };
              };
            }
          ]).lib.registry;
      in
      {
        inherit (empty) central combined validate;
        inherit (empty.settings) centralModules specialArgs;
      };
    expected = {
      central.domain = "central.example.test";
      combined.domain = "central.example.test";
      validate = true;
      centralModules = [ ];
      specialArgs = { };
    };
  };

  testStaticFlakeModuleSharesOneRegistryWithNixosNodes = {
    expr = {
      inherit (consumer.lib.registry) central combined validate;
      endpoint = consumer.nixosConfigurations.backup.config.environment.etc."metrics-endpoint".text;
      localServices = lib.mapAttrs (
        _: node: builtins.attrNames node.config.registry.services
      ) consumer.lib.registry.settings.nodes;
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
      validate = true;
      endpoint = "monitor.example.test:9191";
      localServices = {
        "metrics publisher" = [ "metrics" ];
        "backup reader" = [ "backup" ];
      };
    };
  };
}
