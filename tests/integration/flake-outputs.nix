{
  helpers,
  lib,
  registryLib,
  ...
}:
let
  flake = helpers.rootFlake;
  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];
  outputs = [
    "checks"
    "devShells"
    "formatter"
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

  # The suites test the library that test-context.nix imports from source.
  testRootLibraryIsTheSourceLibrary = {
    expr = flake.lib == registryLib;
    expected = true;
  };

  testRootSystemOutputsCoverOnlyLinuxSystems = {
    expr = lib.genAttrs outputs (name: builtins.attrNames flake.${name});
    expected = lib.genAttrs outputs (_: systems);
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
      nixos = [ (toString ../../nixos/module.nix) ];
      flakeParts = [ (toString ../../flake-module.nix) ];
    };
  };

  testRootChecksKeepTheirNames = {
    expr = lib.genAttrs systems (system: builtins.attrNames flake.checks.${system});
    expected = lib.genAttrs systems (_: [
      "formatting"
      "integration"
      "lint"
      "unit"
    ]);
  };
}
