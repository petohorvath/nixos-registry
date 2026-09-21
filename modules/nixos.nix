# Connect a NixOS node to a caller-owned registry through static settings and shared results.
{ lib, options, ... }:
let
  interface = import ../lib/static-interface.nix { inherit lib; };
in
{
  options.registry =
    lib.mkOption {
      type = lib.types.submodule {
        # The apply function checks contribution definitions against the selected schema.
        freeformType = lib.types.lazyAttrsOf lib.types.raw;
        options = {
          settings = lib.mkOption {
            type = lib.types.submodule {
              options = {
                schemaModules = lib.mkOption {
                  type = lib.types.listOf lib.types.deferredModule;
                  description = "Shared schema modules, also supplied to the project-level registry.";
                };
                specialArgs = lib.mkOption {
                  type = lib.types.lazyAttrsOf lib.types.raw;
                  default = { };
                  description = "Arguments for the shared schema, separate from NixOS module arguments.";
                };
              };
            };
            default = { };
            description = "Shared schema configuration for this node.";
          };
          central = lib.mkOption {
            type = lib.types.raw;
            readOnly = true;
            description = "Central data supplied from the caller's shared registry.";
          };
          combined = lib.mkOption {
            type = lib.types.raw;
            readOnly = true;
            description = "Combined data supplied from the caller's shared registry.";
          };
          validate = lib.mkOption {
            type = lib.types.bool;
            readOnly = true;
            description = "Explicit validation supplied from the caller's shared registry.";
          };
        };
      };
      default = { };
      description = "Local registry contributions, schema settings, and shared results.";
      apply =
        config:
        let
          contributionType = lib.types.submoduleWith {
            modules = config.settings.schemaModules;
            inherit (config.settings) specialArgs;
            shorthandOnlyDefinesConfig = true;
          };
          schemaOptions = contributionType.getSubOptions [ "registry" ];
        in
        interface.checkSchema schemaOptions (
          contributionType.merge [ "registry" ] (
            interface.selectContributions schemaOptions options.registry.definitionsWithLocations
          )
          // lib.getAttrs interface.reservedNames config
        );
    }
    // {
      _nixosRegistry = true;
      _nixosRegistrySelectContributions = interface.selectContributions;
    };
}
