{ lib, mkRegistry }:
let
  tests =
    import ./arguments.nix { inherit lib mkRegistry; }
    // import ./conditions.nix { inherit lib mkRegistry; }
    // import ./minimal.nix { inherit lib mkRegistry; }
    // import ./merging.nix { inherit lib mkRegistry; }
    // import ./ordering.nix { inherit lib mkRegistry; }
    // import ./partial-contributions.nix { inherit lib mkRegistry; }
    // import ./priorities.nix { inherit lib mkRegistry; }
    // import ./schema.nix { inherit lib mkRegistry; }
    // import ./schema-ownership.nix { inherit lib mkRegistry; }
    // import ./examples.nix { inherit lib mkRegistry; };
in
lib.mapAttrs (
  name: test:
  if test.expr == test.expected then
    true
  else
    throw "${name}: expected ${builtins.toJSON test.expected}, got ${builtins.toJSON test.expr}"
) tests
