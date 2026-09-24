{ lib, ... }:
{
  options.backupPaths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Paths included in the backup.
    '';
  };
  config.backupPaths = [ "/schema" ];
}
