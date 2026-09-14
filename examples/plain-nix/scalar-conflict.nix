# Demanding conflicting ordinary host definitions raises a module error.
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib;
    schemaModules = [ ./schema.nix ];
    centralModules = [
      {
        backupDestinations.archive = {
          host = "archive.example.test";
          port = 22;
        };
      }
    ];
    participants."conflicting backup job" = lib.evalModules {
      modules = [
        registry.module
        {
          registry.backupDestinations.archive = {
            host = "different.example.test";
            port = 22;
          };
        }
      ];
    };
  };
in
registry.combined.backupDestinations.archive.host
