/*
  Declare a node's contribution root, typed by the schema of the registry in
  the `registry` module argument. `registry.module` imports this module and
  sets that argument; a node can also receive the registry through its
  `specialArgs`.
*/
{ config, lib, ... }@args:
let
  # Resolve the argument as the module system does, with a clearer error.
  registry =
    args.registry or config._module.args.registry
      or (throw "nixos-registry: the `registry` module argument is not set; import registry.module.");
in
{
  options.registry =
    lib.mkOption {
      type = lib.types.submoduleWith {
        modules = registry.schemaModules;
        specialArgs = registry.moduleArgs;
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "This node's contribution to the shared registry.";
    }
    // {
      # Identify the contribution root without forcing local values.
      _nixosRegistry = true;
    };
}
