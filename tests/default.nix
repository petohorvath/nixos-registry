# Assemble the root checks that run the flake-parts example and source tools.
{
  formatter,
  inputs,
  pkgs,
  system,
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
{
  flake-parts =
    (import ../examples/flake-parts {
      inherit (inputs) nixpkgs;
      inherit system;
      exports = { inherit (inputs.self) flakeModules lib nixosModules; };
      flakeParts = inputs.flake-parts;
    }).checks.${system}.registry;
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
