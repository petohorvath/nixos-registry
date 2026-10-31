{
  fixtures,
  helpers,
  lib,
  registryLib,
  ...
}:
let
  inherit (registryLib) mkRegistry;
  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [ fixtures.schemas.service ];
    centralModules = [ { domain = "example.test"; } ];
  };
  nodes = {
    "metrics publisher" = helpers.mkStaticNode {
      modules = [
        registry.module
        {
          system.stateVersion = "26.05";
          services.prometheus.port = 9191;
        }
        ({ config, registry, ... }: {
          registry.services.metrics = {
            host = "monitor.${registry.central.domain}";
            port = config.services.prometheus.port;
          };
          environment.etc."metrics-endpoint".text = registry.combined.services.metrics.endpoint;
        })
      ];
    };
    # A module from another source imports the static module by path; the
    # registry's module imports the same file.
    "separate source" = helpers.mkStaticNode {
      modules = [
        registry.module
        { system.stateVersion = "26.05"; }
        {
          imports = [ ../../nixos/module.nix ];
          registry.services.api = {
            host = "api.example.test";
            port = 8443;
          };
        }
      ];
    };
  };
  node = nodes."metrics publisher";
in
{
  testNixosNodeContributesAndReadsTheRegistryArgument = {
    expr = {
      local = node.config.registry.services.metrics;
      endpoint = node.config.environment.etc."metrics-endpoint".text;
      inherit (registry) valid;
    };
    expected = {
      local = {
        host = "monitor.example.test";
        port = 9191;
        endpoint = "monitor.example.test:9191";
      };
      endpoint = "monitor.example.test:9191";
      valid = true;
    };
  };

  testNixosRootOverrideAffectsOnlyTheContribution = {
    expr =
      let
        overridden = mkRegistry {
          inherit lib;
          schemaModules = [ fixtures.schemas.service ];
          centralModules = [ { domain = "example.test"; } ];
          nodes."backup override" = override;
        };
        # Overrides its whole contribution; the registry argument and the
        # contribution root's schema stay intact.
        override = helpers.mkStaticNode {
          modules = [
            overridden.module
            { system.stateVersion = "26.05"; }
            ({ registry, ... }: {
              registry = lib.mkForce {
                domain = "override.example.test";
                services.backup = {
                  host = "backup.override.example.test";
                  port = 8022;
                };
              };
              environment.etc."backup-endpoint".text = registry.combined.services.backup.endpoint;
            })
          ];
        };
      in
      {
        endpoint = override.config.environment.etc."backup-endpoint".text;
        local = override.config.registry.services.backup.port;
      };
    expected = {
      endpoint = "backup.override.example.test:8022";
      local = 8022;
    };
  };

  testNixosNodeImportsTheStaticModuleOnce = {
    expr = registry.combined.services.api.endpoint;
    expected = "api.example.test:8443";
  };

  testNixosOptionsDescribeTheSchema = {
    expr = builtins.attrNames (node.options.registry.type.getSubOptions [ ]);
    expected = [
      "_module"
      "domain"
      "services"
    ];
  };

  testNixosNodeUsesCallerSchemaAndSeparateArguments = {
    expr =
      let
        selectedLib = lib.extend (_final: _previous: { registryPortType = lib.types.port; });
        shared = mkRegistry {
          lib = selectedLib;
          schemaModules = [
            ({ lib, schemaLabel, ... }: {
              options = {
                settings = lib.mkOption {
                  type = lib.types.str;
                  default = schemaLabel;
                  description = "A schema field named like a registry setting.";
                };
                port = lib.mkOption {
                  type = lib.registryPortType;
                  description = "A port checked with the consumer's extended library.";
                };
              };
            })
          ];
          moduleArgs = {
            schemaLabel = "shared schema";
            nodePort = 1111;
          };
          nodes."argument owner" = configured;
        };
        configured = helpers.mkStaticNode {
          lib = selectedLib;
          specialArgs.nodePort = 2222;
          modules = [
            shared.module
            ({ nodePort, ... }: {
              registry = {
                port = nodePort;
                settings = "node label";
              };
            })
          ];
        };
      in
      {
        localPort = configured.config.registry.port;
        centralLabel = shared.central.settings;
        inherit (shared) combined valid;
      };
    expected = {
      localPort = 2222;
      centralLabel = "shared schema";
      combined = {
        settings = "node label";
        port = 2222;
      };
      valid = true;
    };
  };
}
