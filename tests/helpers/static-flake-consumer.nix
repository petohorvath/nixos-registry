# A consumer flake whose NixOS nodes share one registry through both static
# modules, with a flake check that validates it.
{
  lib,
  mkProject,
  mkStaticNode,
  nixpkgs,
  system,
}:
{
  schemaModules,
  centralModules ? [ ],
  nodeModules ? { },
  modules ? [ ],
}:
let
  inputs = {
    inherit nixpkgs;
    self = consumer // {
      outPath = ../..;
      inherit inputs;
    };
  };
  consumer = mkProject { inherit inputs; } (
    [
      (
        { config, ... }:
        let
          shared = config.registry;
          commonModule = {
            system.stateVersion = "26.05";
            registry = {
              settings = { inherit (shared.settings) schemaModules specialArgs; };
              inherit (shared) central combined validate;
            };
          };
        in
        {
          systems = [ system ];
          registry.settings = {
            inherit centralModules schemaModules;
            nodes = config.flake.nixosConfigurations;
          };
          flake = {
            lib.registry = shared;
            nixosConfigurations = lib.mapAttrs (
              _: configurationModules: mkStaticNode { modules = [ commonModule ] ++ configurationModules; }
            ) nodeModules;
          };
          perSystem =
            { pkgs, ... }:
            {
              checks.registry =
                assert shared.validate;
                pkgs.runCommand "registry-validation" { } ''
                  touch "$out"
                '';
            };
        }
      )
    ]
    ++ modules
  );
in
consumer
