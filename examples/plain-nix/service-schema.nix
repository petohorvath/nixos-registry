# Caller-owned service records with a required host and port.
{ lib, ... }:
{
  options = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        Domain used by published services.
      '';
    };
    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              host = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Service host.
                '';
              };
              port = lib.mkOption {
                type = lib.types.port;
                description = ''
                  Service port.
                '';
              };
              endpoint = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                default = "${config.host}:${toString config.port}";
                description = ''
                  Endpoint derived from the shared service record.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Named services.
      '';
    };
  };
}
