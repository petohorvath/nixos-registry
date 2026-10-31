# Helpers that evaluate the project's library and modules for the suites.
{
  exports,
  fixtures,
  flake-parts,
  lib,
  nixpkgs,
  system,
}:
let
  inherit (exports.lib) mkRegistry;

  # A NixOS system for the selected system that imports the static NixOS
  # module by its flake export; callers add a registry's generated module.
  mkNixosNode =
    {
      lib ? nixpkgs.lib,
      specialArgs ? { },
      modules,
    }:
    lib.nixosSystem {
      inherit specialArgs;
      modules = [
        exports.nixosModules.default
        { nixpkgs.hostPlatform = system; }
      ]
      ++ modules;
    };

  # A flake-parts project that imports the static flake module.
  mkProject =
    {
      inputs ? { },
      specialArgs ? { },
    }:
    modules:
    flake-parts.lib.mkFlake {
      inputs = {
        inherit nixpkgs;
        self.outPath = ../..;
      }
      // inputs;
      inherit specialArgs;
    } { imports = [ exports.flakeModules.default ] ++ modules; };

  mkStaticConsumer = import ./static-flake-consumer.nix {
    inherit
      lib
      mkProject
      mkNixosNode
      nixpkgs
      system
      ;
  };
in
{
  inherit mkNixosNode mkProject mkStaticConsumer;

  # A plain node that imports only the static NixOS module, without a registry.
  mkUnregisteredNode =
    modules:
    lib.evalModules {
      modules = [ exports.nixosModules.default ] ++ modules;
    };

  mkStaticCollectionConsumer = import ./static-collection-consumer.nix {
    inherit lib mkStaticConsumer;
  };

  evaluateProperties = args: import ./evaluate-properties.nix ({ inherit lib mkRegistry; } // args);

  diagnostics = import ./diagnostics.nix { inherit fixtures lib mkRegistry; };
}
