{ lib, mkRegistry }:
let
  mkEvaluations = import ../fixtures/evaluate-properties.nix { inherit lib mkRegistry; };
in
{
  testLocallyConfiguredConditionsMatchDirectEvaluation = {
    expr =
      map
        (
          enable:
          let
            schema.options.backupPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Paths included in the backup.";
            };
            publication =
              { config, ... }:
              {
                options.backup = {
                  enable = lib.mkEnableOption "backup path publication";
                  includeCache = lib.mkEnableOption "cache path publication";
                };
                config = {
                  backup.enable = enable;
                  registry = lib.mkIf config.backup.enable (
                    lib.mkMerge [
                      { backupPaths = [ "/enabled" ]; }
                      { backupPaths = lib.mkIf config.backup.includeCache [ "/cache" ]; }
                    ]
                  );
                };
              };
            registry = mkRegistry {
              inherit lib;
              schemaModules = [ schema ];
              participants.publisher = lib.evalModules {
                modules = [
                  registry.module
                  publication
                ];
              };
            };
            direct = lib.evalModules {
              modules = [
                {
                  options.registry = lib.mkOption {
                    type = lib.types.submoduleWith {
                      modules = [ schema ];
                      shorthandOnlyDefinesConfig = true;
                    };
                    default = { };
                    description = "The independent reference's typed contribution root.";
                  };
                }
                publication
              ];
            };
          in
          {
            paths = registry.combined.backupPaths;
            matchesDirect = registry.combined == direct.config.registry;
            inherit (registry) validate;
          }
        )
        [
          false
          true
        ];
    expected = [
      {
        paths = [ ];
        matchesDirect = true;
        validate = true;
      }
      {
        paths = [ "/enabled" ];
        matchesDirect = true;
        validate = true;
      }
    ];
  };

  testConditionalInvalidListsMatchDirectEvaluation = {
    expr =
      map
        (
          enable:
          let
            evaluations = mkEvaluations {
              central = [ { backupPaths = [ "/central" ]; } ];
              publications.publisher = [
                { backupPaths = lib.mkIf enable [ 7 ]; }
              ];
            };
            succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
          in
          {
            combinedSucceeds = succeeds evaluations.combined;
            directSucceeds = succeeds evaluations.direct;
            validationSucceeds = succeeds evaluations.validate;
          }
        )
        [
          false
          true
        ];
    expected = [
      {
        combinedSucceeds = true;
        directSucceeds = true;
        validationSucceeds = true;
      }
      {
        combinedSucceeds = false;
        directSucceeds = false;
        validationSucceeds = false;
      }
    ];
  };

  testDisabledRootOrderingDoesNotForceItsContent = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            (lib.mkIf false (lib.mkAfter (throw "Disabled central ordering was forced.")))
          ];
          publications.publisher = [
            (lib.mkIf false (lib.mkBefore (throw "Disabled participant ordering was forced.")))
            { backupPaths = [ "/enabled" ]; }
          ];
        };
      in
      {
        paths = evaluations.combined.backupPaths;
        matchesDirect = evaluations.combined == evaluations.direct;
        inherit (evaluations) validate;
      };
    expected = {
      paths = [ "/enabled" ];
      matchesDirect = true;
      validate = true;
    };
  };

  testConditionalMergeFragmentsMatchDirectEvaluation = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            (lib.mkIf true { backupPaths = lib.mkBefore [ "/central" ]; })
            (lib.mkIf false (throw "A disabled central contribution was forced."))
          ];
          publications.publisher = [
            (lib.mkMerge [
              (lib.mkIf true { backupPaths = [ "/participant" ]; })
              (lib.mkIf false (throw "A disabled participant contribution was forced."))
              {
                backupPaths = lib.mkMerge [
                  (lib.mkIf true (lib.mkAfter [ "/nested" ]))
                  (lib.mkIf false (throw "A disabled nested value was forced."))
                ];
              }
            ])
          ];
        };
      in
      {
        paths = evaluations.combined.backupPaths;
        matchesDirect = evaluations.combined == evaluations.direct;
        inherit (evaluations) validate;
      };
    expected = {
      paths = [
        "/central"
        "/participant"
        "/nested"
      ];
      matchesDirect = true;
      validate = true;
    };
  };
}
