# A consumer flake whose NixOS nodes share one registry through the static
# flake module's node module, with a flake check that validates it.
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
            imports = [ shared.module ];
            system.stateVersion = "26.05";
          };
        in
        {
          systems = [ system ];
          registry = {
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
                assert shared.valid;
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
