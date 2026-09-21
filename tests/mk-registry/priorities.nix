{ lib, mkRegistry }:
let
  mkEvaluations = import ../fixtures/evaluate-properties.nix { inherit lib mkRegistry schema; };

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

  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
in
{
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

  testCentralAndParticipantsShareRootPrecedence = {
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
