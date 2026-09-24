{
  lib,
  mkRegistry,
  mkNode ?
    { registry, definitions, ... }:
    lib.evalModules {
      modules = [ registry.module ] ++ map (registry: { inherit registry; }) definitions;
    },
  schema ? {
    options.backupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths included in the backup.
      '';
    };
  },
}:
{
  central ? [ ],
  publications ? { },
}:
let
  registry = mkRegistry {
    inherit lib;
    schemaModules = [ schema ];
    centralModules = map (config: { inherit config; }) central;
    nodes = lib.mapAttrs (
      _: definitions:
      mkNode {
        inherit definitions registry;
        schemaModules = [ schema ];
      }
    ) publications;
  };
  # Module-order checks supply their native module boundaries separately.
  direct = lib.evalModules {
    modules = [
      {
        options.registry = lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [ schema ];
            shorthandOnlyDefinesConfig = true;
          };
          default = { };
          description = ''
            The independent reference's typed contribution root.
          '';
        };
        config.registry = lib.mkMerge (central ++ lib.concatLists (builtins.attrValues publications));
      }
    ];
  };
in
{
  inherit (registry) central combined validate;
  direct = direct.config.registry;
}
