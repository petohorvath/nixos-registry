{ lib }:
let
  exports = import ./helpers/plain-exports.nix;
  # A marker the flake inputs' library lacks shows the caller's library is used.
  callerLib = lib.extend (_final: _previous: { registryPathType = lib.types.str; });
  registry = exports.lib.mkRegistry {
    lib = callerLib;
    inherit nodes;
    schemaModules = [
      ({ lib, ... }: {
        options.paths = lib.mkOption {
          type = lib.types.listOf lib.registryPathType;
          default = [ ];
          description = "Paths shared by the path-imported nodes.";
        };
      })
    ];
    centralModules = [ { paths = [ "/srv/central" ]; } ];
  };
  nodes.backup = callerLib.evalModules {
    modules = [
      registry.module
      { registry.paths = lib.mkAfter [ "/srv/backup" ]; }
    ];
  };
in
{
  testLibraryDirectoryExportsOnlyMkRegistry = {
    expr = builtins.attrNames exports.lib;
    expected = [ "mkRegistry" ];
  };

  testLibraryDirectoryUsesCallerLibraryWithoutFlakeInputs = {
    expr = {
      inherit (registry) central combined validate;
      local = nodes.backup.config.registry;
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
