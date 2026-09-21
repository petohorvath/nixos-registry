{ lib, mkRegistry }:
let
  schema = {
    options = {
      backupHost = lib.mkOption {
        type = lib.types.str;
        description = "Backup destination host.";
      };
      backupPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Paths included in the backup.";
      };
    };
  };

  rootSchema.options.registry = lib.mkOption {
    type = lib.types.submoduleWith {
      modules = [ schema ];
      shorthandOnlyDefinesConfig = true;
    };
    default = { };
    description = "The independent reference's typed contribution root.";
  };

  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
in
{
  testCentralCanImportChildrenOfADisabledSchemaModule = {
    expr =
      let
        schemaModules = [
          schema
          {
            imports = [ ./fixtures/disabled-parent.nix ];
            disabledModules = [ ./fixtures/disabled-parent.nix ];
          }
        ];
        centralModules = [
          ./fixtures/central-identity.nix
          { backupHost = "archive.example.test"; }
        ];
        registry = mkRegistry {
          inherit centralModules lib schemaModules;
          nodes = { };
        };
        direct = lib.evalModules { modules = schemaModules ++ centralModules; };
      in
      {
        paths = registry.combined.backupPaths;
        matchesDirect = registry.combined == direct.config;
      };
    expected = {
      paths = [ "/fixture" ];
      matchesDirect = true;
    };
  };

  testSharedSchemaImportsContributeDefinitionsOnlyOnce = {
    expr =
      let
        schemaModules = [ ./fixtures/shared-schema-data.nix ];
        centralModules = [ { imports = schemaModules; } ];
        registry = mkRegistry {
          inherit centralModules lib schemaModules;
          nodes = { };
        };
        direct = lib.evalModules { modules = schemaModules ++ centralModules; };
      in
      {
        centralPaths = registry.central.backupPaths;
        combinedPaths = registry.combined.backupPaths;
        matchesDirect = registry.combined == direct.config;
        inherit (registry) validate;
      };
    expected = {
      centralPaths = [ "/schema" ];
      combinedPaths = [ "/schema" ];
      matchesDirect = true;
      validate = true;
    };
  };

  testCentralModulesRejectMixedConfigurationSyntax = {
    expr =
      let
        centralModules = [
          {
            config.backupHost = "archive.example.test";
            backupPaths = [ "/misplaced" ];
          }
        ];
        registry = mkRegistry {
          inherit centralModules lib;
          schemaModules = [ schema ];
          nodes = { };
        };
        direct = lib.evalModules { modules = [ schema ] ++ centralModules; };
      in
      {
        validationSucceeds = succeeds registry.validate;
        directSucceeds = succeeds direct.config;
      };
    expected = {
      validationSucceeds = false;
      directSucceeds = false;
    };
  };

  testCentralOptionsOnlyModulesKeepMetaDefinitions = {
    expr =
      let
        schemaModules = [
          {
            options.meta = lib.mkOption {
              type = lib.types.str;
              description = "Ordinary shared metadata.";
            };
          }
        ];
        centralModules = [
          {
            options = { };
            meta = "central metadata";
          }
        ];
        registry = mkRegistry {
          inherit centralModules lib schemaModules;
          nodes = { };
        };
        direct = lib.evalModules { modules = schemaModules ++ centralModules; };
      in
      {
        meta = registry.combined.meta;
        matchesDirect = registry.combined == direct.config;
      };
    expected = {
      meta = "central metadata";
      matchesDirect = true;
    };
  };

  testCentralFileModulesRetainExplicitIdentity = {
    expr =
      let
        centralModules = [
          ./fixtures/central-identity.nix
          {
            disabledModules = [ { key = "/central-identity"; } ];
            backupHost = "archive.example.test";
          }
        ];
        registry = mkRegistry {
          inherit centralModules lib;
          schemaModules = [ schema ];
          nodes = { };
        };
        direct = lib.evalModules { modules = [ schema ] ++ centralModules; };
      in
      {
        paths = registry.combined.backupPaths;
        matchesDirect = registry.combined == direct.config;
      };
    expected = {
      paths = [ ];
      matchesDirect = true;
    };
  };

  testCentralLegacyAndCurrentImportsKeepTheirOrder = {
    expr =
      let
        centralModules = [
          {
            backupHost = "archive.example.test";
            imports = [ { backupPaths = [ "/imports" ]; } ];
            require = [ { backupPaths = [ "/require" ]; } ];
          }
        ];
        registry = mkRegistry {
          inherit centralModules lib;
          schemaModules = [ schema ];
          nodes = { };
        };
        direct = lib.evalModules { modules = [ schema ] ++ centralModules; };
      in
      {
        paths = registry.combined.backupPaths;
        matchesDirect = registry.combined == direct.config;
      };
    expected = {
      paths = [
        "/imports"
        "/require"
      ];
      matchesDirect = true;
    };
  };

  testCentralModulesKeepRelativeDisabledModulePaths = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          specialArgs.modulesPath = "/central-modules";
          centralModules = [
            {
              key = "/central-modules/base.nix";
              backupPaths = [ "/discarded" ];
            }
            {
              disabledModules = [ "base.nix" ];
              backupHost = "archive.example.test";
            }
          ];
          nodes = { };
        };
        direct = lib.evalModules {
          specialArgs.modulesPath = "/central-modules";
          modules = [
            rootSchema
            {
              key = "/central-modules/base.nix";
              registry.backupPaths = [ "/discarded" ];
            }
            {
              disabledModules = [ "base.nix" ];
              registry.backupHost = "archive.example.test";
            }
          ];
        };
      in
      {
        inherit (registry) combined validate;
        matchesDirect = registry.combined == direct.config.registry;
      };
    expected = {
      combined = {
        backupHost = "archive.example.test";
        backupPaths = [ ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testCentralRootPrioritiesIgnoreNodes = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [
            { backupPaths = [ "/discarded" ]; }
            { config = lib.mkForce { backupHost = "central.example.test"; }; }
          ];
          nodes = throw "The central view collected nodes.";
        };
        direct = lib.evalModules {
          modules = [
            rootSchema
            { registry.backupPaths = [ "/discarded" ]; }
            { registry = lib.mkForce { backupHost = "central.example.test"; }; }
          ];
        };
      in
      {
        inherit (registry) central;
        matchesDirect = registry.central == direct.config.registry;
      };
    expected = {
      central = {
        backupHost = "central.example.test";
        backupPaths = [ ];
      };
      matchesDirect = true;
    };
  };

  testCentralImportsPreserveRootDefaultsAndSharedArguments = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          specialArgs.centralHost = "archive.example.test";
          centralModules = [
            {
              imports = [
                ({ config, centralHost, ... }: {
                  config = lib.mkDefault {
                    backupHost = centralHost;
                    backupPaths = [ "/${config.backupHost}" ];
                  };
                })
              ];
            }
          ];
          nodes = { };
        };
        direct = lib.evalModules {
          modules = [
            rootSchema
            {
              imports = [
                ({ config, ... }: {
                  registry = lib.mkDefault {
                    backupHost = "archive.example.test";
                    backupPaths = [ "/${config.registry.backupHost}" ];
                  };
                })
              ];
            }
          ];
        };
      in
      {
        inherit (registry) combined validate;
        matchesDirect = registry.combined == direct.config.registry;
      };
    expected = {
      combined = {
        backupHost = "archive.example.test";
        backupPaths = [ "/archive.example.test" ];
      };
      matchesDirect = true;
      validate = true;
    };
  };
}
