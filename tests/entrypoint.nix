# Evaluate all tests or select a named test with nix eval --file.
{
  nixpkgs ? (builtins.getFlake (toString ../.)).inputs.nixpkgs,
  flakeParts ? (builtins.getFlake (toString ../.)).inputs.flake-parts,
  system ? builtins.currentSystem,
  flakePartsExample ? import ../examples/flake-parts/evaluate.nix { inherit nixpkgs; },
}:
import ./. {
  inherit
    flakeParts
    flakePartsExample
    nixpkgs
    system
    ;
  inherit (import ../lib) mkRegistry;
}
