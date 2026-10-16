# Helpers that evaluate the project's library and modules for the suites.
{
  flake-parts,
  lib,
  nixpkgs,
  registryLib,
  system,
}:
let
  inherit (registryLib) mkRegistry;
  exports = {
    lib = registryLib;
    nixosModules.default = ../../nixos/module.nix;
    flakeModules.default = ../../flake-module.nix;
  };

  # A NixOS system for the selected system that imports the static module.
  mkStaticNode =
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
      mkStaticNode
      nixpkgs
      system
      ;
  };
in
{
  inherit mkProject mkStaticConsumer mkStaticNode;

  mkStaticCollectionConsumer = import ./static-collection-consumer.nix {
    inherit lib mkStaticConsumer;
  };

  evaluateProperties = args: import ./evaluate-properties.nix ({ inherit lib mkRegistry; } // args);

  diagnostics = import ./diagnostics.nix { inherit lib mkRegistry; };

  importNixosExample =
    args:
    import ../../examples/nixos (
      {
        inherit mkRegistry nixpkgs system;
      }
      // args
    );

  importStaticNixosExample =
    args: import ../../examples/static-nixos ({ inherit exports nixpkgs system; } // args);

  importFlakePartsExample =
    args:
    import ../../examples/flake-parts (
      {
        inherit
          exports
          flake-parts
          nixpkgs
          system
          ;
      }
      // args
    );

  # The root flake's outputs as consumers see them, from the selected inputs.
  rootFlake = import ./evaluation-inputs.nix {
    path = toString ../..;
    inputs = { inherit flake-parts nixpkgs; };
  };
}
