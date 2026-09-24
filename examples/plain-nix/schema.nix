# The example owns its backup schema; the registry supplies aggregation.
{ lib, ... }:
{
  options.backupDestinations = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            description = ''
              Backup destination host.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = ''
              Backup destination port.
            '';
          };
          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Paths included in the backup.
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      Named backup destinations.
    '';
  };
}
