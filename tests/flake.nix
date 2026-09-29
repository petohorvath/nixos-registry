{ flake, lib }:
let
  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];
  declarationsOf =
    module: optionPath:
    (lib.getAttrFromPath optionPath (lib.evalModules { modules = [ module ]; }).options).declarations;
in
{
  testRootLibraryExportsOnlyMkRegistry = {
    expr = builtins.attrNames flake.lib;
    expected = [ "mkRegistry" ];
  };

  testRootSystemOutputsCoverOnlyLinuxSystems = {
    expr = lib.genAttrs [ "checks" "devShells" "formatter" ] (name: builtins.attrNames flake.${name});
    expected = lib.genAttrs [ "checks" "devShells" "formatter" ] (_: systems);
  };

  testRootModuleExportsDeclareOptionsFromTheirFiles = {
    expr = {
      nixos = declarationsOf flake.nixosModules.default [ "registry" ];
      flakeParts = declarationsOf flake.flakeModules.default [
        "registry"
        "settings"
        "schemaModules"
      ];
    };
    expected = {
      nixos = [ (toString ../nixos/module.nix) ];
      flakeParts = [ (toString ../flake-module.nix) ];
    };
  };

  testRootChecksKeepTheirNames = {
    expr = lib.genAttrs systems (system: builtins.attrNames flake.checks.${system});
    expected = lib.genAttrs systems (_: [
      "diagnostics"
      "evaluation"
      "flake-parts"
      "formatting"
      "lint"
      "ordering"
      "recursion"
      "workflows"
    ]);
  };
}
