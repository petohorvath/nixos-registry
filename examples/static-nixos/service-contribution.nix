/*
  Contributes a configured service and reads shared data through the
  static options.
*/
{ config, ... }:
{
  networking.domain = config.registry.central.domain;
  registry.services.metrics = {
    host = "${config.networking.hostName}.${config.networking.domain}";
    port = config.services.prometheus.port;
  };
  environment.etc."metrics-endpoint".text = config.registry.combined.services.metrics.endpoint;
}
