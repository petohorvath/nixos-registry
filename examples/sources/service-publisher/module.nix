# Contributes the configured service port using the supplied registry.
{
  config,
  lib,
  registry,
  ...
}:
{
  options.port = lib.mkOption {
    type = lib.types.port;
    default = 8443;
    description = "Listening port contributed for the API service.";
  };

  config.registry.services.api = {
    host = "api.${registry.combined.domain}";
    inherit (config) port;
  };
}
