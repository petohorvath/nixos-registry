# The single argument of every nix-unit suite.
{
  nixpkgs,
  # Only the integration entry point passes these.
  flake-parts ? null,
  self ? null,
  system ? null,
}:
let
  inherit (nixpkgs) lib;
  registryLib = import ../lib;
  exports = {
    lib = registryLib;
    nixosModules.default = ../nixos/module.nix;
    flakeModules.default = ../flake-module.nix;
  };
  fixtures = import ./fixtures {
    inherit
      exports
      flake-parts
      lib
      nixpkgs
      system
      ;
  };
in
{
  inherit
    fixtures
    lib
    registryLib
    self
    ;
  pkgs = nixpkgs.legacyPackages.${system};
  helpers = import ./helpers {
    inherit
      exports
      fixtures
      flake-parts
      lib
      nixpkgs
      system
      ;
  };
}
