# Contribute a configured API service through the common static registry import.
{ config, ... }:
{
  networking.hostName = "api";
  networking.domain = config.registry.combined.domain;
  services.prometheus = {
    enable = true;
    port = 8443;
  };
  registry.services.api.port = config.services.prometheus.port;
}
