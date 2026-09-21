# Compose a shared registry with the consumer's module library and named nodes.
{
  config,
  lib,
  options,
  ...
}:
let
  registry = import ../lib/mk-registry.nix {
    inherit lib;
    inherit (config.registry.settings)
      centralModules
      nodes
      schemaModules
      specialArgs
      ;
  };
  # Collection types can otherwise supply empty values for undefined options.
  requireSetting =
    name: value:
    if options.registry.settings.${name}.isDefined then
      value
    else
      throw "nixos-registry: registry.settings.${name} must be set explicitly.";
in
{
  options.registry = {
    settings = {
      schemaModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        apply = requireSetting "schemaModules";
        description = "Shared schema modules, also supplied to each node.";
      };
      nodes = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        apply = requireSetting "nodes";
        description = "Named, complete node evaluation results; an empty set is valid.";
      };
      centralModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "Modules defining shared values outside node contributions.";
      };
      specialArgs = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        description = "Arguments for schema and central modules, separate from node module arguments.";
      };
    };
    central = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Shared data from the schema and central modules only.";
    };
    combined = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Shared data merged from central modules and the selected nodes.";
    };
    validate = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      description = "Explicit validation of all combined data; returns true or raises an evaluation error.";
    };
  };

  config.registry = { inherit (registry) central combined validate; };
}
