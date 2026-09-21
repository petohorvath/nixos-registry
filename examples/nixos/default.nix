# Real NixOS nodes publish configured services through a shared handle.
{
  nixpkgs,
  mkRegistry,
  system ? "x86_64-linux",
  package ? nixpkgs.legacyPackages.${system}.prometheus,
}:
let
  inherit (nixpkgs) lib;

  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [ ../plain-nix/service-schema.nix ];
    centralModules = [ { domain = "example.test"; } ];
  };

  nodes = {
    "metrics publisher" = mkNode {
      serviceName = "metrics";
      hostName = "monitor";
      enable = true;
      port = 9191;
    };
    "standby publisher" = mkNode {
      serviceName = "standby";
      hostName = "spare";
      enable = false;
      port = 9292;
    };
  };

  mkNode =
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
  inherit nodes registry;

  result = {
    inherit (registry) central combined validate;
    clientEndpoints = lib.mapAttrs (_: node: node.config.environment.etc."metrics-endpoint".text) nodes;
  };
}
