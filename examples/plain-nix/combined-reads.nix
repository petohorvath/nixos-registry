# A combined domain supplies a host while central data completes its record.
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib;
    schemaModules = [ ./service-schema.nix ];
    centralModules = [
      {
        domain = "example.test";
        services.api.port = 8443;
      }
    ];
    participants."API publisher" = participant;
  };

  participant = lib.evalModules {
    specialArgs = { inherit registry; };
    modules = [
      registry.module
      (
        { registry, ... }:
        {
          options.clientEndpoint = lib.mkOption {
            type = lib.types.str;
            description = "Client endpoint read from the completed shared record.";
          };
          config = {
            registry.services.api.host = "api.${registry.combined.domain}";
            clientEndpoint = registry.combined.services.api.endpoint;
          };
        }
      )
    ];
  };
in
{
  inherit (registry) combined validate;
  inherit (participant.config) clientEndpoint;
  centralDomain = registry.central.domain;
  localHost = participant.config.registry.services.api.host;
}
