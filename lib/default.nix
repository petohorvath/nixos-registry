/*
  Public library exports. Import this directory by path to use the registry
  constructor with a caller-owned module library, without evaluating any
  flake inputs:

    inherit (import "${nixos-registry}/lib") mkRegistry;
*/
{
  mkRegistry = import ./mk-registry.nix;
}
