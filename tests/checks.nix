{
  flakePartsExample,
  formatter,
  nixpkgs,
  pkgs,
  system,
  tests,
}:
let
  sourceDir = pkgs.lib.cleanSource ../.;
  sourceCheck =
    name: packages: script:
    pkgs.runCommand "registry-${name}" { nativeBuildInputs = packages; } ''
      cp -R ${sourceDir} source
      chmod -R u+w source
      cd source
      ${script}
      touch "$out"
    '';
in
pkgs.lib.mapAttrs
  (
    name: script:
    pkgs.runCommand "registry-${name}" { nativeBuildInputs = [ pkgs.nix ]; } ''
      bash ${script} ${nixpkgs}/lib ${../.} ${../tests} ${system}
      touch "$out"
    ''
  )
  {
    diagnostics = ./diagnostics.sh;
    ordering = ./ordering-failures.sh;
    recursion = ./recursion.sh;
  }
// {
  evaluation =
    assert builtins.deepSeq tests true;
    pkgs.runCommand "registry-evaluation" { } ''
      touch "$out"
    '';
  flake-parts = flakePartsExample.checks.${system}.registry;
  formatting = sourceCheck "formatting" [ formatter ] "registry-fmt --ci";
  lint = sourceCheck "lint" [ pkgs.statix pkgs.deadnix ] ''
    statix check .
    deadnix --fail .
  '';
  workflows = sourceCheck "workflows" [ pkgs.actionlint ] ''
    shopt -s nullglob
    workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
    if (( ''${#workflows[@]} )); then
      actionlint "''${workflows[@]}"
    fi
  '';
}
