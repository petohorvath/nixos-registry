# The linters outside treefmt; treefmt-nix and nix-unit add their own checks.
{ pkgs }:
{
  lint =
    pkgs.runCommand "registry-lint"
      {
        src = ../.;
        nativeBuildInputs = [ pkgs.statix ];
      }
      ''
        cd "$src"
        statix check .
        touch "$out"
      '';
}
