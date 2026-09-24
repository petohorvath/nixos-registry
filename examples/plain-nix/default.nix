# Plain module nodes publish backups and read the shared views.
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib nodes;
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

  nodes = {
    "document backup job" = mkNode (
      { config, registry, ... }:
      {
        options = {
          port = lib.mkOption {
            type = lib.types.port;
            default = 2222;
            description = ''
              Port published for the offsite destination.
            '';
          };
          backupCommand = lib.mkOption {
            type = lib.types.str;
            description = ''
              Example command consuming both shared views.
            '';
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
              inherit (config) port;
            };
          };
        };
      }
    );
    "photo backup job" = mkNode {
      registry.backupDestinations.local = {
        host = "local.example.test";
        port = 8022;
        paths = [ "/srv/photos" ];
      };
    };
  };

  mkNode =
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
  backupCommand = nodes."document backup job".config.backupCommand;
}
