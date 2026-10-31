# Diagnostic helpers and the cases that plain and NixOS nodes share.
# Diagnostics name the option path, node, and available source files; each
# regex lists those facts in message order.
{
  fixtures,
  lib,
  mkRegistry,
}:
let
  fails = expr: msg: {
    inherit expr;
    expectedError.msg = msg;
  };

  # Validates a registry whose nodes `mkNode registry modules` builds from
  # each node's modules.
  validateNodeModules =
    mkNode: nodeModules:
    let
      schemaModules = [
        fixtures.schemas.service
        {
          options.backupPaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Ordered backup paths.";
          };
        }
      ];
      registry = mkRegistry {
        inherit lib;
        inherit schemaModules;
        centralModules = [ { domain = "example.test"; } ];
        nodes = lib.mapAttrs (_: mkNode registry) nodeModules;
      };
    in
    registry.valid;
in
{
  inherit fails validateNodeModules;

  # Contributions at the `registry` root of any node.
  rootCases = validate: {
    testOrderedList =
      fails
        (validate {
          "ordered path publisher" = [
            {
              _file = "/modules/ordered-paths.nix";
              registry = lib.mkMerge [
                { backupPaths = lib.mkBefore [ 42 ]; }
                { backupPaths = lib.mkAfter [ "/srv/documents" ]; }
              ];
            }
          ];
        })
        "`backupPaths\\.\"\\[definition 1-entry 1\\]\"' is not of type[\\s\\S]*`node ordered path publisher: /modules/ordered-paths\\.nix'";

    testModuleControls =
      fails
        (validate {
          "module-control publisher" = [
            {
              _file = "/modules/contribution-controls.nix";
              registry._module.check = false;
            }
          ];
        })
        "`registry` from node `module-control publisher` in `/modules/contribution-controls\\.nix` changes module controls";
  };
}
