# Assemble the named root checks from the evaluation suite, examples, and
# source checks.
{
  flake,
  flakeParts,
  formatter,
  nixpkgs,
  pkgs,
  system,
}:
let
  exports = { inherit (flake) flakeModules lib nixosModules; };
  # The suite and the flake-parts check share this evaluation.
  flakePartsExample = import ../examples/flake-parts {
    inherit
      exports
      flakeParts
      nixpkgs
      system
      ;
  };
  staticNixosExample = import ../examples/static-nixos {
    inherit exports nixpkgs system;
  };
  tests = import ./evaluation.nix {
    inherit
      exports
      flake
      flakeParts
      flakePartsExample
      nixpkgs
      staticNixosExample
      system
      ;
  };
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
      bash ${script} ${nixpkgs}/lib ${../.} ${../.}/tests ${system} ${
        pkgs.lib.optionalString (builtins.elem name [
          "diagnostics"
          "recursion"
        ]) (toString flakeParts.outPath)
      }
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
