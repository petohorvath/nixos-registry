# The test entries of the root checks.
{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  repo = "registry";
  srcDir = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../dev
      ../examples
      ../flake-module.nix
      ../flake.nix
      ../lib
      ../nixos
      ../tests
    ];
  };
  runNixUnit = import ./runners/nix-unit.nix {
    inherit
      inputs
      pkgs
      repo
      srcDir
      ;
  };
in
{
  unit = runNixUnit { kind = "unit"; };
  # Parallel NixOS evaluations need much memory.
  integration = runNixUnit {
    kind = "integration";
    jobs = 2;
  };
}
