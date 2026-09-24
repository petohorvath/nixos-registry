{
  lib,
  flakeParts,
  nixpkgs,
}:
let
  inputs = {
    flake-parts = flakeParts;
    nixpkgs = nixpkgs // {
      legacyPackages = throw "Public exports must not evaluate development tools.";
    };
  };
  self = (import ../flake.nix).outputs (inputs // { inherit self; }) // {
    outPath = ../.;
    inherit inputs;
  };
  inherit (import ../lib) mkRegistry;
  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [
      {
        options.paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Paths shared by the plain-import nodes.
          '';
        };
      }
    ];
    centralModules = [ { paths = [ "/srv/central" ]; } ];
  };
  nodes.backup = lib.evalModules {
    modules = [
      registry.module
      { registry.paths = lib.mkAfter [ "/srv/backup" ]; }
    ];
  };
in
{
  testPublicFlakeExportsWithoutDevelopmentEvaluation = {
    expr = {
      libraryNames = builtins.attrNames self.lib;
      nodeValidation =
        (lib.evalModules {
          modules = [
            self.nixosModules.default
            {
              registry.settings.schemaModules = [ ];
              registry.validate = true;
            }
          ];
        }).config.registry.validate;
      flakeModule = self.flakeModules.default == ../flake-module.nix;
      data =
        (self.lib.mkRegistry {
          inherit lib;
          schemaModules = [ ];
          nodes = { };
        }).combined;
    };
    expected = {
      libraryNames = [ "mkRegistry" ];
      nodeValidation = true;
      flakeModule = true;
      data = { };
    };
  };

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
                  description = ''
                    Schema-owned ${name} through the constructor.
                  '';
                }
              );
            }
          ];
          nodes.generic = lib.evalModules {
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
