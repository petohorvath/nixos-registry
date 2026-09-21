# Local enablement controls publication; list properties order merged paths.
{ lib, mkRegistry }:
let
  mkExample =
    enable:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ ./schema.nix ];
        centralModules = [
          {
            backupDestinations.archive = {
              host = "archive.example.test";
              port = 22;
              paths = lib.mkOrder 1000 [ "/srv/central" ];
            };
          }
        ];
        nodes."document backup job" = node;
      };

      node = lib.evalModules {
        specialArgs = { inherit registry; };
        modules = [
          registry.module
          { backup.enable = enable; }
          (
            { config, registry, ... }:
            {
              options = {
                backup = {
                  enable = lib.mkEnableOption "publication of document backup paths";
                  includeCache = lib.mkEnableOption "publication of cache paths";
                  paths = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ "/srv/documents" ];
                    description = "Locally configured document paths.";
                  };
                };
                backupCommand = lib.mkOption {
                  type = lib.types.str;
                  description = "Example command consuming the combined paths.";
                };
              };
              config = {
                registry = lib.mkIf config.backup.enable (
                  lib.mkMerge [
                    { backupDestinations.archive.paths = lib.mkBefore config.backup.paths; }
                    { backupDestinations.archive.paths = lib.mkAfter [ "/srv/snapshots" ]; }
                    {
                      backupDestinations.archive.paths = lib.mkIf config.backup.includeCache [
                        "/srv/cache"
                      ];
                    }
                  ]
                );
                backupCommand =
                  let
                    destination = registry.combined.backupDestinations.archive;
                  in
                  "backup ${destination.host} ${lib.concatStringsSep " " destination.paths}";
              };
            }
          )
        ];
      };
    in
    {
      inherit (registry) combined validate;
      inherit (node.config) backupCommand;
    };
in
{
  enabled = mkExample true;
  disabled = mkExample false;
}
