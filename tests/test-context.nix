# The single argument of every nix-unit suite.
{
  nixpkgs,
  # Only the integration entry point passes flake-parts and self.
  flake-parts ? null,
  self ? null,
  system,
}:
let
  inherit (nixpkgs) lib;
  registryLib = import ../lib;
in
{
  # The flake itself, for the suite that compares its outputs with the
  # source imports.
  inherit lib registryLib self;
  pkgs = nixpkgs.legacyPackages.${system};
  helpers = import ./helpers {
    inherit
      flake-parts
      lib
      nixpkgs
      registryLib
      system
      ;
  };
  fixtures = import ./fixtures;
}
