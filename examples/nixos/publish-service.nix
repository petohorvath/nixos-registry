# Publish the enabled Prometheus service using its NixOS configuration.
{
  config,
  lib,
  registry,
  serviceName,
  ...
}:
{
  networking.domain = registry.combined.domain;
  environment.etc."metrics-endpoint".text = registry.combined.services.metrics.endpoint;

  registry.services.${serviceName} = lib.mkIf config.services.prometheus.enable {
    host = "${config.networking.hostName}.${config.networking.domain}";
    port = config.services.prometheus.port;
  };
}
