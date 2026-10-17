# The linters outside treefmt; treefmt-nix and nix-unit add their own checks.
{ pkgs }:
let
  inherit (pkgs) runCommand statix;
in
{
  lint = runCommand "registry-lint" { nativeBuildInputs = [ statix ]; } ''
    cd ${../.}
    statix check .
    touch "$out"
  '';
}
