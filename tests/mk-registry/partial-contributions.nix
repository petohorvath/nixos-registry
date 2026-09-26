{ lib, mkRegistry }:
let
  schema = ../../examples/plain-nix/partial-schema.nix;

  mkEvaluations =
    {
      centralModules ? [ ],
      contributions ? { },
    }:
    let
      registry = mkRegistry {
        inherit centralModules lib nodes;
        schemaModules = [ schema ];
      };
      nodes = lib.mapAttrs (
        _: contribution:
        lib.evalModules {
          modules = [
            registry.module
            { registry = contribution; }
          ];
        }
      ) contributions;
      direct = lib.evalModules {
        modules = [ schema ] ++ centralModules ++ builtins.attrValues contributions;
      };
    in
    {
      inherit direct nodes registry;
    };

  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;

  split = mkEvaluations {
    contributions = {
      address.backupDestinations.archive.host = "archive.example.test";
      transport.backupDestinations.archive.port = 2222;
    };
  };

  centralPartial = mkEvaluations {
    centralModules = [
      { backupDestinations.archive.host = "archive.example.test"; }
    ];
    contributions.transport.backupDestinations.archive.port = 2222;
  };

  incomplete = mkEvaluations {
    contributions.address.backupDestinations.archive.host = "archive.example.test";
  };
in
{
  testNodesCompleteEachOthersPartialRecords = {
    expr = {
      combined = split.registry.combined;
      matchesDirect = split.registry.combined == split.direct.config;
      validate = split.registry.validate;
    };
    expected = {
      combined.backupDestinations.archive = {
        host = "archive.example.test";
        port = 2222;
        paths = [ "/srv/default" ];
        endpoint = "archive.example.test:2222";
        command = "backup archive.example.test:2222";
      };
      matchesDirect = true;
      validate = true;
    };
  };

  testNodeCompletesACentralPartialRecord = {
    expr = {
      centralHost = centralPartial.registry.central.backupDestinations.archive.host;
      centralIsComplete = succeeds centralPartial.registry.central;
      matchesDirect = centralPartial.registry.combined == centralPartial.direct.config;
      completedPort = centralPartial.registry.combined.backupDestinations.archive.port;
      validate = centralPartial.registry.validate;
    };
    expected = {
      centralHost = "archive.example.test";
      centralIsComplete = false;
      matchesDirect = true;
      completedPort = 2222;
      validate = true;
    };
  };

  testLocalContributionsRemainIncomplete = {
    expr = {
      host = split.nodes.address.config.registry.backupDestinations.archive.host;
      port = split.nodes.transport.config.registry.backupDestinations.archive.port;
      addressIsComplete = succeeds split.nodes.address.config.registry;
      transportIsComplete = succeeds split.nodes.transport.config.registry;
    };
    expected = {
      host = "archive.example.test";
      port = 2222;
      addressIsComplete = false;
      transportIsComplete = false;
    };
  };

  testIncompleteCombinedRecordsFailLikeDirectEvaluation = {
    expr = {
      combinedSucceeds = succeeds incomplete.registry.combined;
      directSucceeds = succeeds incomplete.direct.config;
      validationSucceeds = succeeds incomplete.registry.validate;
    };
    expected = {
      combinedSucceeds = false;
      directSucceeds = false;
      validationSucceeds = false;
    };
  };

  testSchemaListDefaultAppearsOnceRegardlessOfNodeCount = {
    expr =
      map
        (
          names:
          let
            evaluations = mkEvaluations {
              centralModules = [
                {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                  };
                }
              ];
              contributions = lib.genAttrs names (_: {
                backupDestinations.archive = { };
              });
            };
          in
          {
            paths = evaluations.registry.combined.backupDestinations.archive.paths;
            matchesDirect = evaluations.registry.combined == evaluations.direct.config;
          }
        )
        [
          [ ]
          [ "one" ]
          [
            "one"
            "two"
            "three"
          ]
        ];
    expected = lib.replicate 3 {
      paths = [ "/srv/default" ];
      matchesDirect = true;
    };
  };

  testExplicitPathsMergeWithoutDuplicatingTheSchemaDefault = {
    expr =
      let
        evaluations = mkEvaluations {
          centralModules = [
            { backupDestinations.archive.paths = [ "/central" ]; }
          ];
          contributions = {
            address.backupDestinations.archive = {
              host = "archive.example.test";
              paths = [ "/documents" ];
            };
            transport.backupDestinations.archive = {
              port = 2222;
              paths = [ "/photos" ];
            };
          };
        };
      in
      {
        paths = evaluations.registry.combined.backupDestinations.archive.paths;
        matchesDirect = evaluations.registry.combined == evaluations.direct.config;
      };
    expected = {
      paths = [
        "/central"
        "/documents"
        "/photos"
      ];
      matchesDirect = true;
    };
  };

  testAnExplicitEmptyListReplacesTheSchemaDefault = {
    expr =
      let
        evaluations = mkEvaluations {
          centralModules = [
            {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 2222;
              };
            }
          ];
          contributions.emptyPaths.backupDestinations.archive.paths = [ ];
        };
      in
      {
        paths = evaluations.registry.combined.backupDestinations.archive.paths;
        matchesDirect = evaluations.registry.combined == evaluations.direct.config;
      };
    expected = {
      paths = [ ];
      matchesDirect = true;
    };
  };

  testDerivedAndReadOnlyValuesUseCompletedSharedData = {
    expr =
      map
        (evaluations: {
          endpoint = evaluations.registry.combined.backupDestinations.archive.endpoint;
          command = evaluations.registry.combined.backupDestinations.archive.command;
          matchesDirect = evaluations.registry.combined == evaluations.direct.config;
        })
        [
          split
          centralPartial
        ];
    expected = lib.replicate 2 {
      endpoint = "archive.example.test:2222";
      command = "backup archive.example.test:2222";
      matchesDirect = true;
    };
  };

  testAdditionalReadOnlyDefinitionsFailLikeDirectEvaluation = {
    expr =
      map
        (
          extra:
          let
            evaluations = mkEvaluations extra;
          in
          {
            combinedSucceeds = succeeds evaluations.registry.combined;
            directSucceeds = succeeds evaluations.direct.config;
            validationSucceeds = succeeds evaluations.registry.validate;
          }
        )
        [
          {
            centralModules = [
              { backupDestinations.archive.endpoint = "replacement.example.test:22"; }
            ];
            contributions = {
              address.backupDestinations.archive.host = "archive.example.test";
              transport.backupDestinations.archive.port = 2222;
            };
          }
          {
            centralModules = [
              { backupDestinations.archive.host = "archive.example.test"; }
            ];
            contributions.transport.backupDestinations.archive = {
              port = 2222;
              endpoint = "replacement.example.test:22";
            };
          }
        ];
    expected = lib.replicate 2 {
      combinedSucceeds = false;
      directSucceeds = false;
      validationSucceeds = false;
    };
  };
}
