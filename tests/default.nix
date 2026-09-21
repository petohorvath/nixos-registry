{
  nixpkgs,
  flakePartsExample,
  mkRegistry,
  system,
}:
let
  inherit (nixpkgs) lib;

  tests =
    import ./mk-registry.nix { inherit lib mkRegistry; }
    // import ./check-publication.nix { inherit lib mkRegistry; }
    // import ./wrap-central-module.nix { inherit lib mkRegistry; }
    // import ./static-interface.nix { inherit nixpkgs system; }
    // import ./flake.nix { inherit lib; }
    // import ./modules/flake.nix {
      inherit nixpkgs system;
      flakeParts = flakePartsExample.inputs.flake-parts;
    }
    // import ./modules/nixos.nix { inherit nixpkgs system; }
    // import ./integration/static-reads.nix {
      inherit nixpkgs system;
      flakeParts = flakePartsExample.inputs.flake-parts;
    }
    // import ./integration/nixos.nix {
      inherit mkRegistry nixpkgs system;
    }
    // import ./integration/flake-parts.nix { example = flakePartsExample; }
    // import ./integration/examples.nix { inherit lib mkRegistry; };
in
lib.mapAttrs (
  name: test:
  if test.expr == test.expected then
    true
  else
    throw "${name}: expected ${builtins.toJSON test.expected}, got ${builtins.toJSON test.expr}"
) tests
