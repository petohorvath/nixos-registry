# The single argument of every nix-unit suite.
{
  nixpkgs,
  # Only the integration entry point passes flake-parts.
  flake-parts ? null,
  system,
}:
let
  inherit (nixpkgs) lib;
  registryLib = import ../lib;
  # helpers/evaluation-inputs.nix leaves `_type` off the flakes it rebuilds,
  # and flake-parts reads per-system attributes only from marked flakes.
  nixpkgsFlake = nixpkgs // {
    _type = "flake";
  };
in
{
  inherit lib registryLib;
  pkgs = nixpkgs.legacyPackages.${system};
  helpers = import ./helpers {
    inherit
      flake-parts
      lib
      registryLib
      system
      ;
    nixpkgs = nixpkgsFlake;
  };
  fixtures = import ./fixtures;
}
