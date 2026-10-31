/*
  The static NixOS module's implementation: a node's contribution root, typed
  by the schema of the registry in the `registry` module argument. The
  generated module imports this file directly; `nixos/module.nix` exports it.
*/
{ config, lib, ... }@args:
let
  mkContributionOption = import ./mk-contribution-option.nix { inherit lib; };
  # Resolve the argument as the module system does, with a clearer error.
  registry =
    args.registry or config._module.args.registry
      or (throw "nixos-registry: the `registry` module argument is not set; import registry.module.");
in
{
  options.registry =
    mkContributionOption {
      inherit (registry) schemaModules moduleArgs;
      description = "This node's contribution to the shared registry.";
    }
    // {
      # Identify the contribution root without forcing local values.
      _nixosRegistry = true;
    };
}
