# The linters outside treefmt; treefmt-nix and nix-unit add their own checks.
{ pkgs }:
{
  lint = pkgs.runCommand "registry-lint" { nativeBuildInputs = [ pkgs.statix ]; } ''
    cd ${../.}
    statix check .
    touch "$out"
  '';
}
