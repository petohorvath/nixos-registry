{
  exports,
  flake-parts,
  lib,
  nixpkgs,
  system,
}:
let
  inherit (exports.lib) mkRegistry;
  callPlainExample = path: import path { inherit lib mkRegistry; };
  callNixosExample =
    args: import ../../examples/nixos ({ inherit mkRegistry nixpkgs system; } // args);
in
{
  # Fixture modules by path: tests import, disable, and deduplicate them by
  # path, and diagnostics name their files.
  centralIdentity = ./central-identity.nix;
  disabledParent = ./disabled-parent.nix;
  invalidService = ./invalid-service.nix;
  invalidServiceRecord = ./invalid-service-record.nix;
  requiredEndpoint = ./required-endpoint.nix;
  serviceEndpoints = ./service-endpoints.nix;
  sharedSchemaData = ./shared-schema-data.nix;

  # Example files that suites put into module lists, by path.
  schemas = {
    flake-parts = ../../examples/flake-parts/schema.nix;
    partial = ../../examples/plain-nix/partial-schema.nix;
    service = ../../examples/plain-nix/service-schema.nix;
  };
  sources = {
    backup-client = ../../examples/sources/backup-client/module.nix;
    service-publisher = ../../examples/sources/service-publisher/module.nix;
  };

  # The evaluated examples, built from the source exports.
  examples = {
    collection-laziness = callPlainExample ../../examples/plain-nix/collection-laziness.nix;
    combined-reads = callPlainExample ../../examples/plain-nix/combined-reads.nix;
    conditional-ordering = callPlainExample ../../examples/plain-nix/conditional-ordering.nix;
    flake-parts = import ../../examples/flake-parts {
      inherit
        exports
        flake-parts
        nixpkgs
        system
        ;
    };
    nixos = callNixosExample { };
    # The NixOS example with its service package from another package set.
    nixos-with-package = package: callNixosExample { inherit package; };
    partial-contributions = callPlainExample ../../examples/plain-nix/partial-contributions.nix;
    plain-nix = callPlainExample ../../examples/plain-nix;
    priorities = callPlainExample ../../examples/plain-nix/priorities.nix;
    scalar-conflict = callPlainExample ../../examples/plain-nix/scalar-conflict.nix;
    static-nixos = import ../../examples/static-nixos { inherit exports nixpkgs system; };
    value-cycle = callPlainExample ../../examples/plain-nix/value-cycle.nix;
  };
}
