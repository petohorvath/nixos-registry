{ example }:
let
  api = example.lib.participants."api publisher".config;
  backup = example.lib.participants."backup consumer".config;
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
      validate = true;
    };
  };

  testSeparateSourceParticipantsKeepLocalContributionsDistinct = {
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
      sharedEndpoint = backup.registry.combined.services.api.endpoint;
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
        inherit (example.inputs.nixpkgs) lib;
        registryFlake = (import "${example.inputs.nixos-registry}/flake.nix").outputs { };
        registry = registryFlake.lib.mkRegistry {
          inherit lib participants;
          schemaModules = [ ../examples/flake-parts/schema.nix ];
          centralModules = [ { domain = "example.test"; } ];
        };
        participants =
          builtins.mapAttrs
            (
              _: participantModule:
              lib.evalModules {
                specialArgs = { inherit registry; };
                modules = [
                  registry.module
                  participantModule
                ];
              }
            )
            {
              "api publisher" = example.inputs.servicePublisher.modules.generic.default;
              "backup consumer" = example.inputs.backupClient.modules.generic.default;
            };
      in
      {
        endpoints = builtins.mapAttrs (_: service: service.endpoint) registry.combined.services;
        backupCommand = participants."backup consumer".config.backupCommand;
        inherit (registry) validate;
      };
    expected = {
      endpoints = {
        api = "api.example.test:8443";
        backup = "backup.example.test:8022";
      };
      backupCommand = "backup --api api.example.test:8443";
      validate = true;
    };
  };
}
