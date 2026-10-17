{ nixpkgs }:
let
  testContext = import ../test-context.nix { inherit nixpkgs; };
in
{
  check-contribution = import ./check-contribution.nix testContext;
  diagnostics = import ./diagnostics.nix testContext;
  get-active-module-keys = import ./get-active-module-keys.nix testContext;
  lib = import ./lib.nix testContext;
  mk-registry = {
    arguments = import ./mk-registry/arguments.nix testContext;
    conditions = import ./mk-registry/conditions.nix testContext;
    laziness = import ./mk-registry/laziness.nix testContext;
    merging = import ./mk-registry/merging.nix testContext;
    mk-registry = import ./mk-registry/mk-registry.nix testContext;
    ordering = import ./mk-registry/ordering.nix testContext;
    partial-contributions = import ./mk-registry/partial-contributions.nix testContext;
    priorities = import ./mk-registry/priorities.nix testContext;
    schema = import ./mk-registry/schema.nix testContext;
    validation = import ./mk-registry/validation.nix testContext;
  };
  plain-nix-examples = import ./plain-nix-examples.nix testContext;
  recursion = import ./recursion.nix testContext;
  wrap-central-module = import ./wrap-central-module.nix testContext;
}
