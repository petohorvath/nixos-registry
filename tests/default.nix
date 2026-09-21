{
  nixpkgs,
  flakePartsExample,
  mkRegistry,
  system,
}:
let
  inherit (nixpkgs) lib;

  tests =
    import ./arguments.nix { inherit lib mkRegistry; }
    // import ./conditions.nix { inherit lib mkRegistry; }
    // import ./flake-parts.nix { example = flakePartsExample; }
    // import ./laziness.nix { inherit lib mkRegistry; }
    // import ./minimal.nix { inherit lib mkRegistry; }
    // import ./merging.nix { inherit lib mkRegistry; }
    // import ./modules/flake.nix {
      inherit nixpkgs system;
      flakeParts = flakePartsExample.inputs.flake-parts;
    }
    // import ./modules/nixos.nix { inherit nixpkgs system; }
    // import ./nixos.nix {
      inherit mkRegistry nixpkgs system;
    }
    // import ./ordering.nix { inherit lib mkRegistry; }
    // import ./partial-contributions.nix { inherit lib mkRegistry; }
    // import ./plain-import.nix { inherit lib; }
    // import ./priorities.nix { inherit lib mkRegistry; }
    // import ./schema.nix { inherit lib mkRegistry; }
    // import ./schema-ownership.nix { inherit lib mkRegistry; }
    // import ./validation.nix { inherit lib mkRegistry; }
    // import ./examples.nix { inherit lib mkRegistry; };
in
lib.mapAttrs (
  name: test:
  if test.expr == test.expected then
    true
  else
    throw "${name}: expected ${builtins.toJSON test.expected}, got ${builtins.toJSON test.expr}"
) tests
