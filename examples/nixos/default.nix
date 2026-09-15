# Real NixOS participants publish configured services through a shared handle.
{
  nixpkgs,
  mkRegistry,
  system ? "x86_64-linux",
  package ? nixpkgs.legacyPackages.${system}.prometheus,
}:
let
  inherit (nixpkgs) lib;

  registry = mkRegistry {
    inherit lib participants;
    schemaModules = [ ../plain-nix/service-schema.nix ];
    centralModules = [ { domain = "example.test"; } ];
  };

  participants = {
    "metrics publisher" = mkParticipant {
      serviceName = "metrics";
      hostName = "monitor";
      enable = true;
      port = 9191;
    };
    "standby publisher" = mkParticipant {
      serviceName = "standby";
      hostName = "spare";
      enable = false;
      port = 9292;
    };
  };

  mkParticipant =
    {
      serviceName,
      hostName,
      enable,
      port,
    }:
    lib.nixosSystem {
      specialArgs = { inherit registry serviceName; };
      modules = [
        registry.module
        ./publish-service.nix
        {
          nixpkgs.hostPlatform = system;
          networking.hostName = hostName;
          system.stateVersion = "26.05";
          services.prometheus = { inherit enable package port; };
        }
      ];
    };
in
{
  inherit participants registry;

  result = {
    inherit (registry) central combined validate;
    clientEndpoints = lib.mapAttrs (
      _: participant: participant.config.environment.etc."metrics-endpoint".text
    ) participants;
  };
}
