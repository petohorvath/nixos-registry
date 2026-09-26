{ lib, mkRegistry }:
let
  schemaModules = [
    {
      options.service = lib.mkOption {
        type = lib.types.submodule [
          {
            options.backupPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Paths included in the backup.";
            };
          }
          ./fixtures/disabled-parent.nix
          { disabledModules = [ ./fixtures/disabled-parent.nix ]; }
        ];
        default = { };
        description = "Service data with a disabled schema module.";
      };
    }
  ];
  mkNode =
    registry: contribution:
    lib.evalModules {
      modules = [
        registry.module
        { registry.service = contribution; }
      ];
    };
in
{
  testContributionsCanDisableInactiveSchemaModules = {
    expr =
      let
        registry = mkRegistry {
          inherit lib schemaModules;
          nodes.backup = mkNode registry (_: {
            # The disabled parent hides this schema module.
            disabledModules = [ { key = "/central-identity"; } ];
            config.backupPaths = [ "/node" ];
          });
        };
      in
      {
        inherit (registry) validate;
        paths = registry.combined.service.backupPaths;
      };
    expected = {
      paths = [ "/node" ];
      validate = true;
    };
  };
}
