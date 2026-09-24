# An ordinary-flake consumer with one shared registry and a static NixOS import.
{
  nixpkgs,
  system ? "x86_64-linux",
  registryFlake ? {
    lib = import ../../lib;
    nixosModules.default = ../../nixos/module.nix;
  },
}:
let
  inherit (nixpkgs) lib;
  settings.schemaModules = [ ../plain-nix/service-schema.nix ];

  registry = registryFlake.lib.mkRegistry (
    settings
    // {
      inherit lib nodes;
      centralModules = [ { domain = "example.test"; } ];
    }
  );

  commonModule = {
    imports = [ registryFlake.nixosModules.default ];
    registry = {
      inherit settings;
      inherit (registry) central combined validate;
    };
  };

  nodes."metrics publisher" = lib.nixosSystem {
    modules = [
      commonModule
      ./publish-service.nix
      {
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
        networking.hostName = "monitor";
        services.prometheus = {
          enable = true;
          port = 9191;
        };
      }
    ];
  };
in
{
  inherit nodes registry;
  result = {
    inherit (registry) central combined validate;
    endpoint = nodes."metrics publisher".config.environment.etc."metrics-endpoint".text;
  };
}
