{ lib, registryLib, ... }:
let
  inherit (registryLib) mkRegistry;
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
    inherit lib nodes;
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

  nodes = {
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
  testCentralDataExcludesNodes = {
    expr = registry.central;
    expected.backupDestinations.archive = {
      host = "archive.example.test";
      port = 22;
    };
  };

  testCollectsCentralAndNamedNodes = {
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

  testEmptyNodesUseConstructorDefaults = {
    expr =
      let
        empty = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes = { };
        };
      in
      {
        inherit (empty) central combined valid;
      };
    expected = {
      central.backupDestinations = { };
      combined.backupDestinations = { };
      valid = true;
    };
  };

  testModuleSuppliesTheRegistryArgument = {
    expr =
      let
        mirrored = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [
            {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 22;
              };
            }
          ];
          nodes.mirror = lib.evalModules {
            modules = [
              mirrored.module
              (
                { registry, ... }:
                {
                  registry.backupDestinations.mirror = {
                    host = "mirror.example.test";
                    inherit (registry.central.backupDestinations.archive) port;
                  };
                }
              )
            ];
          };
        };
      in
      mirrored.combined.backupDestinations.mirror;
    expected = {
      host = "mirror.example.test";
      port = 22;
    };
  };

  testReturnsItsInputsAndResults = {
    expr =
      let
        empty = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes = { };
        };
      in
      {
        names = builtins.attrNames empty;
        inherit (empty) centralModules moduleArgs nodes;
        schemaModules = empty.schemaModules == [ schema ];
      };
    expected = {
      names = [
        "central"
        "centralModules"
        "combined"
        "module"
        "moduleArgs"
        "nodes"
        "schemaModules"
        "valid"
      ];
      centralModules = [ ];
      moduleArgs = { };
      nodes = { };
      schemaModules = true;
    };
  };

  testLocalRegistryContainsOnlyTheNodeContribution = {
    expr = nodes."offsite backup job".config.registry;
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
          nodes = { };
        };
      in
      invalid.combined.backupDestinations.invalid.port;
    expectedError.msg = "`backupDestinations\\.invalid\\.port' is not of type `16 bit unsigned integer";
  };

  testValidatesCompleteCombinedData = {
    expr = registry.valid;
    expected = true;
  };
}
