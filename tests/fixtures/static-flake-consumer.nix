{
  nixpkgs,
  flakeParts,
  system,
}:
{
  schemaModules,
  centralModules ? [ ],
  nodeModules ? { },
  modules ? [ ],
}:
let
  exports = import ../helpers/plain-exports.nix;
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
        imports = [ exports.nixosModules.default ];
        nixpkgs.hostPlatform = system;
        system.stateVersion = "26.05";
        registry = {
          settings = { inherit (shared.settings) schemaModules specialArgs; };
          inherit (shared) central combined validate;
        };
      };
    in
    {
      imports = [ exports.flakeModules.default ] ++ modules;
      systems = [ system ];
      registry.settings = {
        inherit centralModules schemaModules;
        nodes = config.flake.nixosConfigurations;
      };
      flake = {
        lib.registry = shared;
        nixosConfigurations = nixpkgs.lib.mapAttrs (
          _: configurationModules:
          nixpkgs.lib.nixosSystem {
            modules = [ commonModule ] ++ configurationModules;
          }
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
  );
in
consumer
