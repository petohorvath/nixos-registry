{
  fixtures,
  lib,
  pkgs,
  registryLib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  example = fixtures.examples.flake-parts;
  api = example.lib.nodes."api publisher".config;
  backup = example.lib.nodes."backup consumer".config;
in
{
  testFlakePartsExampleEvaluatesAndValidates = {
    expr = example.lib.result;
    expected = {
      central = {
        domain = "example.test";
        services.api.host = "api.example.test";
      };
      combined = {
        domain = "example.test";
        services = {
          api = {
            host = "api.example.test";
            port = 8443;
            endpoint = "api.example.test:8443";
          };
          backup = {
            host = "backup.example.test";
            port = 8022;
            endpoint = "backup.example.test:8022";
          };
        };
      };
      backupCommand = "backup --api api.example.test:8443";
      valid = true;
    };
  };

  # Evaluating the check's derivation demands registry validation.
  testFlakePartsExampleCheckEvaluates = {
    expr = builtins.isString example.checks.${system}.registry.drvPath;
    expected = true;
  };

  testSeparateSourceNodesKeepLocalContributionsDistinct = {
    expr = {
      "api publisher" = {
        port = api.services.prometheus.port;
        serviceNames = builtins.attrNames api.registry.services;
      };
      "backup consumer" = {
        port = builtins.head backup.services.openssh.ports;
        serviceNames = builtins.attrNames backup.registry.services;
      };
    };
    expected = {
      "api publisher" = {
        port = 8443;
        serviceNames = [ "api" ];
      };
      "backup consumer" = {
        port = 8022;
        serviceNames = [ "backup" ];
      };
    };
  };

  testSeparateSourceExampleCompletesPartialRecords = {
    expr = {
      centralPortDefined = (builtins.tryEval example.lib.registry.central.services.api.port).success;
      localHostDefined = (builtins.tryEval api.registry.services.api.host).success;
      localApiPort = api.registry.services.api.port;
      localBackup = { inherit (backup.registry.services.backup) host port; };
      sharedEndpoint = example.lib.registry.combined.services.api.endpoint;
    };
    expected = {
      centralPortDefined = false;
      localHostDefined = false;
      localApiPort = 8443;
      localBackup = {
        host = "backup.example.test";
        port = 8022;
      };
      sharedEndpoint = "api.example.test:8443";
    };
  };

  testSeparateSourceGenericModulesKeepConstructorAccess = {
    expr =
      let
        registry = registryLib.mkRegistry {
          inherit lib nodes;
          schemaModules = [ fixtures.schemas.flake-parts ];
          centralModules = [ { domain = "example.test"; } ];
        };
        nodes =
          builtins.mapAttrs
            (
              _: nodeModule:
              lib.evalModules {
                modules = [
                  registry.module
                  nodeModule
                ];
              }
            )
            {
              "api publisher" = fixtures.sources.service-publisher;
              "backup consumer" = fixtures.sources.backup-client;
            };
      in
      {
        endpoints = builtins.mapAttrs (_: service: service.endpoint) registry.combined.services;
        backupCommand = nodes."backup consumer".config.backupCommand;
        inherit (registry) valid;
      };
    expected = {
      endpoints = {
        api = "api.example.test:8443";
        backup = "backup.example.test:8022";
      };
      backupCommand = "backup --api api.example.test:8443";
      valid = true;
    };
  };
}
