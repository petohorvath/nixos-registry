# The root checks: the test entries and the source tools.
{
  formatter,
  inputs,
  pkgs,
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
pkgs.lib.attrsets.unionOfDisjoint (import ../tests { inherit inputs pkgs; }) {
  formatting = sourceCheck "formatting" [ formatter ] "registry-fmt --ci";
  lint =
    sourceCheck "lint"
      [
        pkgs.actionlint
        pkgs.deadnix
        pkgs.statix
      ]
      ''
        statix check .
        deadnix --fail .
        shopt -s nullglob
        workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
        if (( ''${#workflows[@]} )); then
          actionlint "''${workflows[@]}"
        fi
      '';
}
