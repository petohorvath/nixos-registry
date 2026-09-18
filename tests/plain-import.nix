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
