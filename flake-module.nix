/*
  Compose a registry at the project level from the consumer's module library,
  shared schema, central modules, and named nodes. `registry` has the shape
  that `mkRegistry` returns: the settings, plus the read-only node module,
  central data, combined data, and validation.
*/
{
  config,
  lib,
  options,
  ...
}:
let
  registry = import ./lib/mk-registry.nix {
    inherit lib;
    inherit (config.registry)
      centralModules
      moduleArgs
      nodes
      schemaModules
      ;
  };
  # Collection types can otherwise supply empty values for undefined options.
  requireSetting =
    name: value:
    if options.registry.${name}.isDefined then
      value
    else
      throw "nixos-registry: registry.${name} must be set explicitly.";
in
{
  options.registry = {
    schemaModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      apply = requireSetting "schemaModules";
      description = "Shared schema modules.";
    };
    nodes = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      apply = requireSetting "nodes";
      description = ''
        Named, complete node evaluation results; an empty set is valid.
      '';
    };
    centralModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      default = [ ];
      description = ''
        Modules defining shared values outside node contributions.
      '';
    };
    moduleArgs = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = ''
        Arguments for schema and central modules, separate from node module
        arguments.
      '';
    };
    module = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = ''
        The node module, which declares a node's contribution root and passes
        this registry as the `registry` module argument.
      '';
    };
    central = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Shared data from the schema and central modules only.";
    };
    combined = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = ''
        Shared data merged from central modules and the selected nodes.
      '';
    };
    valid = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      description = ''
        Explicit validation of all combined data; returns true or raises an
        evaluation error.
      '';
    };
  };

  config.registry = {
    inherit (registry)
      central
      combined
      module
      valid
      ;
  };
}
