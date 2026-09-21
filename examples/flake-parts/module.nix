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

  participants = {
    "api publisher" = mkParticipant inputs.servicePublisher.nixosModules.default;
    "backup consumer" = mkParticipant inputs.backupClient.nixosModules.default;
  };

  mkParticipant =
    participantModule:
    inputs.nixpkgs.lib.nixosSystem {
      modules = [
        commonModule
        participantModule
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
    inherit participants;
    schemaModules = [ ./schema.nix ];
    centralModules = [
      ({ config, ... }: {
        domain = "example.test";
        services.api.host = "api.${config.domain}";
      })
    ];
  };

  flake.lib = {
    inherit participants;
    registry = shared;
    result = {
      # The central API record lacks its participant's port and derived endpoint.
      central = {
        inherit (shared.central) domain;
        services.api.host = shared.central.services.api.host;
      };
      inherit (shared) combined validate;
      backupCommand = participants."backup consumer".config.environment.etc."backup-command".text;
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
