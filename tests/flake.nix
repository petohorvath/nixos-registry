{ lib }:
let
  mkRegistry = ((import ../flake.nix).outputs { }).lib.mkRegistry;
  registry = mkRegistry {
    inherit lib participants;
    schemaModules = [
      {
        options.paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Paths shared by the plain-import participants.";
        };
      }
    ];
    centralModules = [ { paths = [ "/srv/central" ]; } ];
  };
  participants.backup = lib.evalModules {
    modules = [
      registry.module
      { registry.paths = lib.mkAfter [ "/srv/backup" ]; }
    ];
  };
in
{
  testConstructorKeepsSchemaNamesReservedByStaticModules = {
    expr =
      let
        legacy = mkRegistry {
          inherit lib;
          schemaModules = [
            {
              options = lib.genAttrs [ "settings" "central" "combined" "validate" ] (
                name:
                lib.mkOption {
                  type = lib.types.str;
                  description = "Schema-owned ${name} through the constructor.";
                }
              );
            }
          ];
          participants.generic = lib.evalModules {
            modules = [
              legacy.module
              {
                registry = {
                  settings = "local settings";
                  central = "local central";
                  combined = "local combined";
                  validate = "local validate";
                };
              }
            ];
          };
        };
      in
      {
        inherit (legacy) combined validate;
      };
    expected = {
      combined = {
        settings = "local settings";
        central = "local central";
        combined = "local combined";
        validate = "local validate";
      };
      validate = true;
    };
  };

  testPlainImportUsesCallerLibraryWithoutDevelopmentInputs = {
    expr = {
      inherit (registry) central combined validate;
      local = participants.backup.config.registry;
    };
    expected = {
      central.paths = [ "/srv/central" ];
      combined.paths = [
        "/srv/central"
        "/srv/backup"
      ];
      local.paths = [ "/srv/backup" ];
      validate = true;
    };
  };
}
