{ lib, mkRegistry }:
let
  mkEvaluations = import ./fixtures/evaluate-properties.nix { inherit lib mkRegistry schema; };

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
          participants = { };
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
          participants = { };
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
          participants = { };
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
          participants = { };
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
          participants = { };
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
          participants = { };
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
          participants = { };
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

  testCentralViewUsesTheSameContributionRootWithoutParticipants = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          centralModules = [
            { backupPaths = [ "/discarded" ]; }
            { config = lib.mkForce { backupHost = "central.example.test"; }; }
          ];
          participants = throw "The central view collected participants.";
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
          participants = { };
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

  testWeakerContributionsCannotCompleteAStrongerPartialRecord = {
    expr =
      let
        evaluations = mkEvaluations {
          publications = {
            address = [ (lib.mkDefault { backupHost = "discarded.example.test"; }) ];
            paths = [ { backupPaths = [ "/selected" ]; } ];
          };
        };
      in
      {
        combinedSucceeds = succeeds evaluations.combined;
        directSucceeds = succeeds evaluations.direct;
        validationSucceeds = succeeds evaluations.validate;
      };
    expected = {
      combinedSucceeds = false;
      directSucceeds = false;
      validationSucceeds = false;
    };
  };

  testEqualContributionPrioritiesRetainScalarConflicts = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ (lib.mkForce { backupHost = "central.example.test"; }) ];
          publications.publisher = [
            (lib.mkForce { backupHost = "participant.example.test"; })
          ];
        };
      in
      {
        combinedSucceeds = succeeds evaluations.combined;
        directSucceeds = succeeds evaluations.direct;
        validationSucceeds = succeeds evaluations.validate;
      };
    expected = {
      combinedSucceeds = false;
      directSucceeds = false;
      validationSucceeds = false;
    };
  };

  testNestedPrioritiesResolveAfterEqualContributionPriorities = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            (lib.mkDefault {
              backupHost = lib.mkForce "central.example.test";
              backupPaths = [ "/central" ];
            })
          ];
          publications.publisher = [
            (lib.mkDefault {
              backupHost = lib.mkDefault "default.example.test";
              backupPaths = lib.mkDefault [ "/default" ];
            })
            (lib.mkDefault {
              backupHost = lib.mkOverride 40 "selected.example.test";
              backupPaths = [ "/participant" ];
            })
          ];
        };
      in
      {
        inherit (evaluations) combined validate;
        matchesDirect = evaluations.combined == evaluations.direct;
      };
    expected = {
      combined = {
        backupHost = "selected.example.test";
        backupPaths = [
          "/participant"
          "/central"
        ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testCompetingDefinitionsWithinAParticipantKeepRootPriorities = {
    expr =
      let
        evaluations = mkEvaluations {
          publications = {
            publisher = [
              (lib.mkDefault {
                backupHost = "discarded.example.test";
                backupPaths = throw "A discarded contribution was forced.";
              })
              (lib.mkOverride 80 {
                backupHost = "selected.example.test";
                backupPaths = [ "/selected" ];
              })
            ];
            other = [ { backupHost = "ordinary.example.test"; } ];
          };
        };
      in
      {
        inherit (evaluations) combined validate;
        matchesDirect = evaluations.combined == evaluations.direct;
      };
    expected = {
      combined = {
        backupHost = "selected.example.test";
        backupPaths = [ "/selected" ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testNumericContributionPrioritiesSelectWholeRecords = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ (lib.mkForce { backupHost = "central.example.test"; }) ];
          publications = {
            first = [
              (lib.mkOverride 20 {
                backupHost = "selected.example.test";
                backupPaths = [ "/first" ];
              })
            ];
            second = [ (lib.mkOverride 20 { backupPaths = [ "/second" ]; }) ];
            weaker = [
              (lib.mkOverride 30 {
                backupHost = "weaker.example.test";
                backupPaths = [ "/weaker" ];
              })
            ];
          };
        };
      in
      {
        inherit (evaluations) combined validate;
        matchesDirect = evaluations.combined == evaluations.direct;
      };
    expected = {
      combined = {
        backupHost = "selected.example.test";
        backupPaths = [
          "/second"
          "/first"
        ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testCentralContributionHasTheSameRootPrecedenceAsParticipants = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ (lib.mkForce { backupHost = "central.example.test"; }) ];
          publications.publisher = [
            {
              backupHost = lib.mkOverride 10 "participant.example.test";
              backupPaths = [ "/participant" ];
            }
          ];
        };
      in
      {
        inherit (evaluations) combined validate;
        matchesDirect = evaluations.combined == evaluations.direct;
      };
    expected = {
      combined = {
        backupHost = "central.example.test";
        backupPaths = [ ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testForcedContributionReplacesWeakerContributionsInFull = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            {
              backupHost = lib.mkForce "central.example.test";
              backupPaths = [ "/central" ];
            }
          ];
          publications = {
            ordinary = [ { backupPaths = lib.mkForce [ "/participant" ]; } ];
            forced = [ (lib.mkForce { backupHost = "forced.example.test"; }) ];
          };
        };
      in
      {
        inherit (evaluations) combined validate;
        matchesDirect = evaluations.combined == evaluations.direct;
      };
    expected = {
      combined = {
        backupHost = "forced.example.test";
        backupPaths = [ ];
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testContributionDefaultYieldsToCentralDefinitions = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ { backupHost = "central.example.test"; } ];
          publications.publisher = [
            (lib.mkDefault { backupHost = "participant.example.test"; })
          ];
        };
      in
      {
        host = evaluations.combined.backupHost;
        matchesDirect = evaluations.combined == evaluations.direct;
        inherit (evaluations) validate;
      };
    expected = {
      host = "central.example.test";
      matchesDirect = true;
      validate = true;
    };
  };

  testNestedDefaultsYieldToOrdinaryDefinitionsAcrossSources = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ { backupHost = lib.mkDefault "central.example.test"; } ];
          publications.publisher = [ { backupHost = "participant.example.test"; } ];
        };
      in
      {
        host = evaluations.combined.backupHost;
        matchesDirect = evaluations.combined == evaluations.direct;
        inherit (evaluations) validate;
      };
    expected = {
      host = "participant.example.test";
      matchesDirect = true;
      validate = true;
    };
  };
}
