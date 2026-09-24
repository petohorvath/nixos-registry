/*
  Declares required backup fields and values derived from a completed record.
  Defaults and derived values are evaluated in each shared view.
*/
{ lib, ... }:
{
  options.backupDestinations = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
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
              default = [ "/srv/default" ];
              description = ''
                Paths included in the backup.
              '';
            };
            endpoint = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "${config.host}:${toString config.port}";
              description = ''
                Endpoint derived from the completed destination.
              '';
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = ''
                Backup command derived from the shared endpoint.
              '';
            };
          };
          config.command = "backup ${config.endpoint}";
        }
      )
    );
    default = { };
    description = ''
      Named backup destinations.
    '';
  };
}
