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

  central = {
    backupHost = "archive.example.test";
    backupPaths = [ "/central" ];
  };
  contributions = {
    documents = {
      backupHost = "archive.example.test";
      backupPaths = [ "/documents" ];
    };
    photos = {
      backupHost = "archive.example.test";
      backupPaths = [ "/photos" ];
    };
  };

  direct = lib.evalModules {
    modules = [
      schema
      central
    ]
    ++ builtins.attrValues contributions;
  };

  mkTestRegistry =
    contributions:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ schema ];
        centralModules = [ central ];
        nodes = lib.mapAttrs (
          _: contribution:
          lib.evalModules {
            modules = [
              registry.module
              { registry = contribution; }
            ];
          }
        ) contributions;
      };
    in
    registry;

  conflict = mkTestRegistry {
    disagreeing.backupHost = "different.example.test";
  };
in
{
  testMergesListsLikeDirectEvaluation = {
    expr = (mkTestRegistry contributions).combined.backupPaths;
    expected = direct.config.backupPaths;
  };

  testAcceptsMatchingScalarDefinitions = {
    expr = (mkTestRegistry contributions).combined.backupHost;
    expected = "archive.example.test";
  };

  testRejectsScalarConflictsLikeDirectEvaluation = {
    expr = (builtins.tryEval conflict.combined.backupHost).success;
    expected =
      (builtins.tryEval
        (lib.evalModules {
          modules = [
            schema
            central
            { backupHost = "different.example.test"; }
          ];
        }).config.backupHost
      ).success;
  };

  testValidationRejectsConflictingData = {
    expr = conflict.validate;
    expectedError.msg = "`backupHost' has conflicting definition values[\\s\\S]*`node disagreeing: ";
  };
}
