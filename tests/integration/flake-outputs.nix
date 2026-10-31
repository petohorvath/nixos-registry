{
  lib,
  registryLib,
  self,
  ...
}:
let
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
    (lib.getAttrFromPath optionPath
      (lib.evalModules {
        modules = [ module ];
        # The node module's contribution root takes its type from the registry.
        specialArgs.registry = {
          schemaModules = [ ];
          moduleArgs = { };
        };
      }).options
    ).declarations;
in
{
  testRootLibraryExportsOnlyMkRegistry = {
    expr = builtins.attrNames self.lib;
    expected = [ "mkRegistry" ];
  };

  # The suites test the library that test-context.nix imports from source.
  testRootLibraryIsTheSourceLibrary = {
    expr = self.lib == registryLib;
    expected = true;
  };

  testRootSystemOutputsCoverOnlyLinuxSystems = {
    expr = lib.genAttrs outputs (name: builtins.attrNames self.${name}) // {
      tests = builtins.attrNames self.tests.systems;
    };
    expected = lib.genAttrs (outputs ++ [ "tests" ]) (_: systems);
  };

  testRootModuleExportsDeclareOptionsFromTheirFiles = {
    expr = {
      nixos = declarationsOf self.nixosModules.default [ "registry" ];
      flakeParts = declarationsOf self.flakeModules.default [
        "registry"
        "schemaModules"
      ];
    };
    expected = {
      nixos = [ (toString ../../nixos/module.nix) ];
      flakeParts = [ (toString ../../flake-module.nix) ];
    };
  };

  testRootChecksKeepTheirNames = {
    expr = lib.genAttrs systems (system: builtins.attrNames self.checks.${system});
    expected = lib.genAttrs systems (_: [
      "lint"
      "nix-unit"
      "treefmt"
    ]);
  };
}
