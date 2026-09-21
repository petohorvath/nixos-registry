{
  nixpkgs,
  flakeParts,
  system,
}:
{
  schemaModules,
  centralModules ? [ ],
  participantModules ? { },
  modules ? [ ],
}:
let
  registryFlake = (import ../../flake.nix).outputs { };
  inputs = {
    inherit nixpkgs;
    self = consumer // {
      outPath = ../..;
      inherit inputs;
    };
  };
  consumer = flakeParts.lib.mkFlake { inherit inputs; } (
    { config, ... }:
    let
      shared = config.registry;
      commonModule = {
        imports = [ registryFlake.nixosModules.default ];
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
        registry = {
          settings = { inherit (shared.settings) schemaModules specialArgs; };
          inherit (shared) central combined validate;
        };
      };
    in
    {
      imports = [ registryFlake.flakeModules.default ] ++ modules;
      systems = [ system ];
      registry.settings = {
        inherit centralModules schemaModules;
        participants = config.flake.nixosConfigurations;
      };
      flake = {
        lib.registry = shared;
        nixosConfigurations = nixpkgs.lib.mapAttrs (
          _: modules:
          nixpkgs.lib.nixosSystem {
            modules = [ commonModule ] ++ modules;
          }
        ) participantModules;
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
  );
in
consumer
