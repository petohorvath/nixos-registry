/*
  An ordinary-flake consumer with one shared registry and a static NixOS
  import.
*/
{
  exports,
  nixpkgs,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;
  settings.schemaModules = [ ../plain-nix/service-schema.nix ];

  registry = exports.lib.mkRegistry (
    settings
    // {
      inherit lib nodes;
      centralModules = [ { domain = "example.test"; } ];
    }
  );

  commonModule = {
    imports = [ exports.nixosModules.default ];
    registry = {
      inherit settings;
      inherit (registry) central combined validate;
    };
  };

  nodes."metrics publisher" = lib.nixosSystem {
    modules = [
      commonModule
      ./service-contribution.nix
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
