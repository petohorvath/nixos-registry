/*
  Flake-parts adoption with caller-owned schemas and nodes defined in
  separate sources. The caller evaluates each source's NixOS module and
  exposes registry validation as a flake check.
*/
{
  exports,
  flakeParts,
  nixpkgs,
  system ? "x86_64-linux",
}:
flakeParts.lib.mkFlake { inputs.self.outPath = ./.; } (
  { config, ... }:
  let
    # `systems` contains only the selected system.
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (config) registry;
    commonModule = {
      imports = [ exports.nixosModules.default ];
      nixpkgs.hostPlatform = system;
      system.stateVersion = "26.05";
      registry = {
        settings = { inherit (registry.settings) schemaModules specialArgs; };
        inherit (registry) central combined validate;
      };
    };

    mkNode =
      nodeModule:
      nixpkgs.lib.nixosSystem {
        modules = [
          commonModule
          nodeModule
        ];
      };

    # Each source directory stands in for a separate repository.
    nodes = {
      "api publisher" = mkNode ../sources/service-publisher/nixos.nix;
      "backup consumer" = mkNode ../sources/backup-client/nixos.nix;
    };
  in
  {
    imports = [ exports.flakeModules.default ];
    systems = [ system ];

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
      inherit nodes registry;
      result = {
        # The central API record lacks its node's port and derived endpoint.
        central = {
          inherit (registry.central) domain;
          services.api.host = registry.central.services.api.host;
        };
        inherit (registry) combined validate;
        backupCommand = nodes."backup consumer".config.environment.etc."backup-command".text;
      };
    };

    perSystem.checks.registry =
      assert registry.validate;
      pkgs.runCommand "flake-parts-registry-validation" { } ''
        touch "$out"
      '';
  }
)
