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
    expr = lib.genAttrs [ "checks" "devShells" "formatter" "legacyPackages" ] (
      name: builtins.attrNames flake.${name}
    );
    expected = lib.genAttrs [ "checks" "devShells" "formatter" "legacyPackages" ] (_: systems);
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

  testRootLegacyPackagesExposeTestsAndExamples = {
    expr = lib.genAttrs systems (
      system:
      let
        focused = flake.legacyPackages.${system};
      in
      {
        names = builtins.attrNames focused;
        examples = builtins.attrNames focused.examples;
      }
    );
    expected = lib.genAttrs systems (_: {
      names = [
        "examples"
        "tests"
      ];
      examples = [
        "collectionLaziness"
        "combinedReads"
        "conditionalOrdering"
        "default"
        "flakeParts"
        "nixos"
        "partialContributions"
        "priorities"
        "scalarConflicts"
        "staticNixos"
        "valueCycles"
      ];
    });
  };
}
