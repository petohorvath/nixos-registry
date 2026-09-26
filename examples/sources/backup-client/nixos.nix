/*
  Contributes a backup service and reads the API endpoint from another
  node.
*/
{ config, ... }:
{
  networking.hostName = "backup";
  networking.domain = config.registry.central.domain;
  services.openssh = {
    enable = true;
    ports = [ 8022 ];
  };
  registry.services.backup = {
    host = "${config.networking.hostName}.${config.networking.domain}";
    port = builtins.head config.services.openssh.ports;
  };
  environment.etc."backup-command".text =
    "backup --api ${config.registry.combined.services.api.endpoint}";
}
