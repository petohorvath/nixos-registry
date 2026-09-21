# The caller evaluates source-owned modules and exposes registry validation.
{ config, inputs, ... }:
let
  registryFlake = (import "${inputs.nixos-registry}/flake.nix").outputs { };
  shared = config.registry;
  commonModule = {
    imports = [ registryFlake.nixosModules.default ];
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.05";
    registry = {
      settings = { inherit (shared.settings) schemaModules specialArgs; };
      inherit (shared) central combined validate;
    };
  };

  nodes = {
    "api publisher" = mkNode inputs.servicePublisher.nixosModules.default;
    "backup consumer" = mkNode inputs.backupClient.nixosModules.default;
  };

  mkNode =
    nodeModule:
    inputs.nixpkgs.lib.nixosSystem {
      modules = [
        commonModule
        nodeModule
      ];
    };
in
{
  imports = [ registryFlake.flakeModules.default ];
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  registry.settings = {
    inherit nodes;
    schemaModules = [ ./schema.nix ];
    centralModules = [
      ({ config, ... }: {
        domain = "example.test";
        services.api.host = "api.${config.domain}";
      })
    ];
  };

  flake.lib = {
    inherit nodes;
    registry = shared;
    result = {
      # The central API record lacks its node's port and derived endpoint.
      central = {
        inherit (shared.central) domain;
        services.api.host = shared.central.services.api.host;
      };
      inherit (shared) combined validate;
      backupCommand = nodes."backup consumer".config.environment.etc."backup-command".text;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      checks.registry =
        assert shared.validate;
        pkgs.runCommand "flake-parts-registry-validation" { } ''
          touch "$out"
        '';
    };
}
