# Contributes a configured API service and reads the shared domain.
{ config, registry, ... }:
{
  networking.hostName = "api";
  networking.domain = registry.combined.domain;
  services.prometheus = {
    enable = true;
    port = 8443;
  };
  registry.services.api.port = config.services.prometheus.port;
}
