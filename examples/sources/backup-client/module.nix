# Publishes a backup service and consumes a separately sourced API endpoint.
{
  config,
  lib,
  registry,
  ...
}:
{
  options = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 8022;
      description = ''
        Listening port published for the backup service.
      '';
    };
    backupCommand = lib.mkOption {
      type = lib.types.str;
      description = ''
        Backup command consuming both shared data views.
      '';
    };
  };

  config = {
    registry.services.backup = {
      host = "backup.${registry.central.domain}";
      inherit (config) port;
    };
    backupCommand = "backup --api ${registry.combined.services.api.endpoint}";
  };
}
