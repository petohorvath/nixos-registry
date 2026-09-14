# Plain module participants publish backups and read the shared views.
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib participants;
    schemaModules = [ ./schema.nix ];
    centralModules = [
      {
        backupDestinations.archive = {
          host = "archive.example.test";
          port = 22;
          paths = [ "/srv/central" ];
        };
      }
    ];
  };

  participants = {
    "document backup job" = mkParticipant (
      { config, registry, ... }:
      {
        options = {
          port = lib.mkOption {
            type = lib.types.port;
            default = 2222;
            description = "Port published for the offsite destination.";
          };
          backupCommand = lib.mkOption {
            type = lib.types.str;
            description = "Example command consuming both shared views.";
          };
        };
        config = {
          backupCommand =
            "backup ${registry.central.backupDestinations.archive.host} "
            + registry.combined.backupDestinations.local.host;
          registry.backupDestinations = {
            archive = {
              host = "archive.example.test";
              port = 22;
              paths = [ "/srv/documents" ];
            };
            offsite = {
              host = "offsite.example.test";
              port = config.port;
            };
          };
        };
      }
    );
    "photo backup job" = mkParticipant {
      registry.backupDestinations.local = {
        host = "local.example.test";
        port = 8022;
        paths = [ "/srv/photos" ];
      };
    };
  };

  mkParticipant =
    module:
    lib.evalModules {
      specialArgs = { inherit registry; };
      modules = [
        registry.module
        module
      ];
    };
in
{
  inherit (registry) central combined validate;
  backupCommand = participants."document backup job".config.backupCommand;
}
