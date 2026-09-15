# The caller evaluates source-owned modules and exposes registry validation.
{ inputs, lib, ... }:
let
  registry = inputs.nixos-registry.lib.mkRegistry {
    inherit lib participants;
    schemaModules = [ ./schema.nix ];
    centralModules = [ { domain = "example.test"; } ];
  };

  participants = {
    "api publisher" = mkParticipant inputs.servicePublisher.modules.generic.default;
    "backup consumer" = mkParticipant inputs.backupClient.modules.generic.default;
  };

  mkParticipant =
    participantModule:
    lib.evalModules {
      specialArgs = { inherit registry; };
      modules = [
        registry.module
        participantModule
      ];
    };
in
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  flake.lib = {
    inherit participants registry;
    result = {
      inherit (registry) central combined validate;
      backupCommand = participants."backup consumer".config.backupCommand;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      checks.registry =
        assert registry.validate;
        pkgs.runCommand "flake-parts-registry-validation" { } ''
          touch "$out"
        '';
    };
}
