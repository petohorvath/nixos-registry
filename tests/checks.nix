{
  flakePartsExamples,
  formatter,
  pkgs,
  sources,
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
builtins.mapAttrs (
  channel: results:
  assert builtins.deepSeq results true;
  pkgs.runCommand "registry-${channel}" { } ''
    touch "$out"
  ''
) tests
// pkgs.lib.mapAttrs' (
  channel: example: pkgs.lib.nameValuePair "flake-parts-${channel}" example.checks.${system}.registry
) flakePartsExamples
// pkgs.lib.concatMapAttrs (
  channel: source:
  pkgs.lib.mapAttrs'
    (
      name: script:
      pkgs.lib.nameValuePair "${name}-${channel}" (
        pkgs.runCommand "registry-${name}-${channel}" { nativeBuildInputs = [ pkgs.nix ]; } ''
          bash ${script} ${source}/lib ${../.} ${../tests}
          touch "$out"
        ''
      )
    )
    {
      diagnostics = ./diagnostics.sh;
      ordering = ./ordering-failures.sh;
      recursion = ./recursion.sh;
    }
) sources
// {
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
