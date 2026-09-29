# Assemble the evaluation suite; a failing case throws with both values.
{
  exports,
  flakePartsExample,
  inputs,
  staticNixosExample,
  system,
}:
let
  inherit (inputs) nixpkgs;
  flakeParts = inputs.flake-parts;
  inherit (exports.lib) mkRegistry;
  inherit (nixpkgs) lib;
  pathExports = import ./helpers/plain-exports.nix;
  pathFlakePartsExample = import ../examples/flake-parts {
    inherit flakeParts nixpkgs system;
    exports = pathExports;
  };
  importFlakeModuleTests =
    exports:
    import ./flake-module.nix {
      inherit
        exports
        flakeParts
        nixpkgs
        system
        ;
    };
  importNixosModuleTests = exports: import ./nixos/module.nix { inherit exports nixpkgs system; };
  importFlakePartsExampleTests =
    exports: example:
    import ./integration/flake-parts.nix {
      inherit example lib;
      inherit (exports.lib) mkRegistry;
    };

  # Rerun selected scenarios with the public exports loaded by path.
  selectPathImportedTests =
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
    // import ./flake.nix {
      inherit lib;
      flake = inputs.self;
    }
    // import ./lib.nix { inherit lib; }
    // importFlakeModuleTests exports
    // importNixosModuleTests exports
    // selectPathImportedTests (importFlakeModuleTests pathExports) [
      "testStaticFlakeModuleSharesOneRegistryWithNixosNodes"
      "testStaticFlakeModuleUsesConsumerLibraryAndSeparateArguments"
    ]
    // selectPathImportedTests (importNixosModuleTests pathExports) [
      "testStaticNixosModuleContributesAndReadsSharedResults"
      "testStaticNixosModuleUsesCallerSchemaAndSeparateArguments"
    ]
    // import ./integration/static-nixos.nix { example = staticNixosExample; }
    // import ./integration/static-reads.nix { inherit flakeParts nixpkgs system; }
    // import ./integration/nixos.nix {
      inherit mkRegistry nixpkgs system;
    }
    // importFlakePartsExampleTests exports flakePartsExample
    // selectPathImportedTests (importFlakePartsExampleTests pathExports pathFlakePartsExample) [
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
