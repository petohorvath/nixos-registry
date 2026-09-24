{
  inputs,
  pkgs,
  system,
  formatter,
}:
let
  inherit (inputs) nixpkgs;
  flakePartsExample = import ../examples/flake-parts/evaluate.nix { inherit nixpkgs; };
in
import ../tests/checks.nix {
  inherit
    flakePartsExample
    formatter
    nixpkgs
    pkgs
    system
    ;
  tests = import ../tests/entrypoint.nix {
    inherit flakePartsExample nixpkgs system;
    flakeParts = inputs.flake-parts;
  };
}
