{ lib, mkRegistry }:
let
  schema = {
    options.backupDestinations = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Backup destination host.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Backup destination port.";
            };
          };
        }
      );
      default = { };
      description = "Named backup destinations.";
    };
  };

  registry = mkRegistry {
    inherit lib participants;
    schemaModules = [ schema ];
    centralModules = [
      {
        backupDestinations.archive = {
          host = "archive.example.test";
          port = 22;
        };
      }
    ];
  };

  participants = {
    "offsite backup job" = lib.evalModules {
      modules = [
        registry.module
        {
          registry.backupDestinations.offsite = {
            host = "offsite.example.test";
            port = 2222;
          };
        }
      ];
    };
    "storage pool" = lib.evalModules {
      modules = [
        registry.module
        {
          registry.backupDestinations.local = {
            host = "local.example.test";
            port = 8022;
          };
        }
      ];
    };
  };
in
{
  testCentralViewExcludesParticipants = {
    expr = registry.central;
    expected.backupDestinations.archive = {
      host = "archive.example.test";
      port = 22;
    };
  };

  testCollectsCentralAndNamedParticipants = {
    expr = registry.combined;
    expected.backupDestinations = {
      archive = {
        host = "archive.example.test";
        port = 22;
      };
      local = {
        host = "local.example.test";
        port = 8022;
      };
      offsite = {
        host = "offsite.example.test";
        port = 2222;
      };
    };
  };

  testEmptyParticipantsUseConstructorDefaults = {
    expr =
      let
        empty = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          participants = { };
        };
      in
      {
        inherit (empty) central combined validate;
      };
    expected = {
      central.backupDestinations = { };
      combined.backupDestinations = { };
      validate = true;
    };
  };

  testLocalRegistryContainsOnlyTheParticipantContribution = {
    expr = participants."offsite backup job".config.registry;
    expected.backupDestinations.offsite = {
      host = "offsite.example.test";
      port = 2222;
    };
  };

  testRejectsADemandedInvalidPort = {
    expr =
      let
        invalid = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [
            {
              backupDestinations.invalid = {
                host = "invalid.example.test";
                port = "not a port";
              };
            }
          ];
          participants = { };
        };
      in
      (builtins.tryEval invalid.combined.backupDestinations.invalid.port).success;
    expected = false;
  };

  testValidatesCompleteCombinedData = {
    expr = registry.validate;
    expected = true;
  };
}
