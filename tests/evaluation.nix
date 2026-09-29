# Assemble the evaluation suite; a failing case throws with both values.
{
  flake,
  flakeParts,
  nixpkgs,
  system,
}:
let
  exports = { inherit (flake) flakeModules lib nixosModules; };
  inherit (exports.lib) mkRegistry;
  inherit (nixpkgs) lib;
  pathExports = import ./helpers/plain-exports.nix;
  flakeModuleTests =
    moduleExports:
    import ./flake-module.nix {
      inherit flakeParts nixpkgs system;
      exports = moduleExports;
    };
  nixosModuleTests =
    moduleExports:
    import ./nixos/module.nix {
      inherit nixpkgs system;
      exports = moduleExports;
    };
  flakePartsExampleTests =
    exampleExports:
    import ./integration/flake-parts.nix {
      inherit lib;
      inherit (exampleExports.lib) mkRegistry;
      example = import ../examples/flake-parts {
        inherit flakeParts nixpkgs system;
        registry = exampleExports;
      };
    };

  # Rerun selected scenarios with the public exports loaded by path.
  pathImportedTests =
    tests: names:
    lib.mapAttrs' (name: lib.nameValuePair "testPathImported${lib.removePrefix "test" name}") (
      lib.getAttrs names tests
    );

  tests =
    import ./mk-registry.nix { inherit lib mkRegistry; }
    // import ./check-contribution.nix { inherit lib mkRegistry; }
    // import ./wrap-central-module.nix { inherit lib mkRegistry; }
    // import ./get-active-module-keys.nix { inherit lib mkRegistry; }
    // import ./static-interface.nix { inherit nixpkgs system; }
    // import ./flake.nix { inherit flake lib; }
    // import ./lib.nix { inherit lib; }
    // flakeModuleTests exports
    // nixosModuleTests exports
    // pathImportedTests (flakeModuleTests pathExports) [
      "testStaticFlakeModuleSharesOneRegistryWithNixosNodes"
      "testStaticFlakeModuleUsesConsumerLibraryAndSeparateArguments"
    ]
    // pathImportedTests (nixosModuleTests pathExports) [
      "testStaticNixosModuleContributesAndReadsSharedResults"
      "testStaticNixosModuleUsesCallerSchemaAndSeparateArguments"
    ]
    // import ./integration/static-reads.nix { inherit flakeParts nixpkgs system; }
    // import ./integration/nixos.nix {
      inherit mkRegistry nixpkgs system;
    }
    // flakePartsExampleTests exports
    // pathImportedTests (flakePartsExampleTests pathExports) [
      "testFlakePartsExampleEvaluatesAndValidates"
      "testSeparateSourceNodesKeepLocalContributionsDistinct"
      "testSeparateSourceExampleCompletesPartialRecords"
      "testSeparateSourceGenericModulesKeepConstructorAccess"
    ]
    // import ./integration/examples.nix { inherit lib mkRegistry; };
in
lib.mapAttrs (
  name: test:
  if test.expr == test.expected then
    true
  else
    throw "${name}: expected ${builtins.toJSON test.expected}, got ${builtins.toJSON test.expr}"
) tests
