# The nix-unit suite for one system, nested by source module.
{ inputs, system }:
let
  inherit (inputs) nixpkgs self;
  inherit (nixpkgs) lib;
  flakeParts = inputs.flake-parts;
  exports = { inherit (self) flakeModules lib nixosModules; };
  pathExports = import ./helpers/plain-exports.nix;
  inherit (exports.lib) mkRegistry;

  exportTests = exports: {
    flakeModule = import ./flake-module.nix {
      inherit
        exports
        flakeParts
        nixpkgs
        system
        ;
    };
    nixosModule = import ./nixos/module.nix { inherit exports nixpkgs system; };
    flakePartsExample = import ./integration/flake-parts.nix {
      inherit lib;
      inherit (exports.lib) mkRegistry;
      example = import ../examples/flake-parts {
        inherit
          exports
          flakeParts
          nixpkgs
          system
          ;
      };
    };
  };
in
{
  mkRegistry = import ./mk-registry.nix { inherit lib mkRegistry; };
  checkContribution = import ./check-contribution.nix { inherit lib mkRegistry; };
  wrapCentralModule = import ./wrap-central-module.nix { inherit lib mkRegistry; };
  getActiveModuleKeys = import ./get-active-module-keys.nix { inherit lib mkRegistry; };
  staticInterface = import ./static-interface.nix { inherit nixpkgs system; };
  flake = import ./flake.nix {
    inherit lib;
    flake = self;
  };
  lib = import ./lib.nix { inherit lib; };
  diagnostics = import ./diagnostics.nix {
    inherit
      exports
      flakeParts
      nixpkgs
      system
      ;
  };
  orderingFailures = import ./ordering-failures.nix { inherit exports nixpkgs system; };
  recursion = import ./recursion.nix {
    inherit
      exports
      flakeParts
      nixpkgs
      system
      ;
  };
  integration = {
    staticNixos = import ./integration/static-nixos.nix {
      example = import ../examples/static-nixos { inherit exports nixpkgs system; };
    };
    staticReads = import ./integration/static-reads.nix { inherit flakeParts nixpkgs system; };
    nixos = import ./integration/nixos.nix { inherit mkRegistry nixpkgs system; };
    examples = import ./integration/examples.nix { inherit lib mkRegistry; };
  };
}
// exportTests exports
// {
  pathImported = exportTests pathExports;
}
