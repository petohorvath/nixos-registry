{ nixpkgs, system }:
let
  inherit (nixpkgs) lib;
  registryFlake = (import ../flake.nix).outputs { };
  schemaModules = [ ../examples/plain-nix/partial-schema.nix ];
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;

  mkEvaluations =
    {
      central ? [ ],
      publications ? { },
      wiringProperty ? lib.id,
      participantModules ? { },
    }:
    let
      registry = registryFlake.lib.mkRegistry {
        inherit lib participants schemaModules;
        centralModules = map (config: { inherit config; }) central;
      };
      participants = lib.mapAttrs (
        name: definitions:
        lib.nixosSystem {
          modules = [
            registryFlake.nixosModules.default
            {
              nixpkgs.hostPlatform = system;
              registry = wiringProperty {
                settings = { inherit schemaModules; };
                inherit (registry) central combined validate;
              };
            }
          ]
          ++ map (registry: { inherit registry; }) definitions
          ++ (participantModules.${name} or [ ]);
        }
      ) publications;
      direct = lib.evalModules {
        modules = [
          {
            options.registry = lib.mkOption {
              type = lib.types.submoduleWith {
                modules = schemaModules;
                shorthandOnlyDefinesConfig = true;
              };
              default = { };
              description = "The independent reference's typed contribution root.";
            };
            config.registry = lib.mkMerge (central ++ lib.concatLists (builtins.attrValues publications));
          }
        ];
      };
    in
    {
      inherit participants registry;
      direct = direct.config.registry;
    };
in
{
  testStaticDiscardedContributionDoesNotForceItsProperties = {
    expr =
      map
        (
          discarded:
          let
            evaluations = mkEvaluations {
              wiringProperty = lib.mkDefault;
              central = [
                (lib.mkForce {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                  };
                })
              ];
              publications.publisher = [ (lib.mkDefault discarded) ];
            };
          in
          {
            matchesDirect = evaluations.registry.combined == evaluations.direct;
            inherit (evaluations.registry) validate;
          }
        )
        [
          (lib.mkIf (throw "A discarded condition was forced.") {
            backupDestinations.archive.host = "discarded.example.test";
          })
          (lib.mkMerge (throw "A discarded merge was forced."))
          (lib.mkMerge [ (throw "A discarded merge fragment was forced.") ])
          (lib.mkForce (throw "A discarded override payload was forced."))
          (lib.mkDefinition {
            file = "/discarded-definition.nix";
            value = throw "A discarded definition was forced.";
          })
        ];
    expected = lib.replicate 5 {
      matchesDirect = true;
      validate = true;
    };
  };

  testStaticDiscardedOrderingDoesNotForceItsContent = {
    expr =
      map
        (
          source:
          let
            selected = lib.mkForce {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 2222;
              };
            };
            discarded = lib.mkBefore (throw "A discarded ordered contribution was forced.");
            evaluations = mkEvaluations {
              central = [ (if source == "central" then discarded else selected) ];
              publications.publisher = [ (if source == "participant" then discarded else selected) ];
            };
          in
          {
            matchesDirect = evaluations.registry.combined == evaluations.direct;
            inherit (evaluations.registry) validate;
          }
        )
        [
          "central"
          "participant"
        ];
    expected = lib.replicate 2 {
      matchesDirect = true;
      validate = true;
    };
  };

  testStaticWholeContributionPrioritiesMatchDirectEvaluation = {
    expr =
      map
        (
          property:
          let
            evaluations = mkEvaluations {
              wiringProperty = property;
              central = [
                (lib.mkDefault {
                  backupDestinations.discarded = {
                    host = "discarded.example.test";
                    port = 22;
                  };
                })
              ];
              publications.publisher = [
                (property {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                  };
                })
              ];
              publications.reader = [ ];
            };
          in
          {
            names = builtins.attrNames evaluations.registry.combined.backupDestinations;
            matchesDirect = evaluations.registry.combined == evaluations.direct;
            sharedRead =
              evaluations.participants.reader.config.registry.combined.backupDestinations.archive.endpoint;
            inherit (evaluations.registry) validate;
          }
        )
        [
          lib.mkDefault
          lib.id
          lib.mkForce
          (lib.mkOverride 20)
        ];
    expected =
      map
        (names: {
          inherit names;
          matchesDirect = true;
          sharedRead = "archive.example.test:2222";
          validate = true;
        })
        [
          [
            "archive"
            "discarded"
          ]
          [ "archive" ]
          [ "archive" ]
          [ "archive" ]
        ];
  };

  testStaticForcedWiringDoesNotOverrideContributions = {
    expr =
      let
        evaluations = mkEvaluations {
          wiringProperty = lib.mkForce;
          central = [
            {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 2222;
              };
            }
          ];
          publications.reader = [ ];
        };
      in
      {
        matchesDirect = evaluations.registry.combined == evaluations.direct;
        endpoint =
          evaluations.participants.reader.config.registry.combined.backupDestinations.archive.endpoint;
        inherit (evaluations.registry) validate;
      };
    expected = {
      matchesDirect = true;
      endpoint = "archive.example.test:2222";
      validate = true;
    };
  };

  testStaticRootOverridesDiscardWeakerFields = {
    expr =
      let
        evaluations = mkEvaluations {
          wiringProperty = lib.mkForce;
          central = [ { backupDestinations.archive.host = "discarded.example.test"; } ];
          publications.publisher = [ (lib.mkForce { backupDestinations.archive.port = 2222; }) ];
        };
      in
      {
        combined = succeeds evaluations.registry.combined;
        direct = succeeds evaluations.direct;
        validate = succeeds evaluations.registry.validate;
      };
    expected = {
      combined = false;
      direct = false;
      validate = false;
    };
  };

  testStaticExplicitEmptyRootStillOverridesWeakerContributions = {
    expr =
      let
        evaluations = mkEvaluations {
          wiringProperty = lib.mkForce;
          central = [
            {
              backupDestinations.archive = {
                host = "discarded.example.test";
                port = 22;
              };
            }
          ];
          publications.publisher = [ (lib.mkForce { }) ];
        };
      in
      {
        inherit (evaluations.registry) combined validate;
        matchesDirect = evaluations.registry.combined == evaluations.direct;
      };
    expected = {
      combined.backupDestinations = { };
      matchesDirect = true;
      validate = true;
    };
  };

  testStaticRootOverridesAlsoSelectLocalWiring = {
    expr =
      let
        evaluations = mkEvaluations {
          publications.publisher = [
            (lib.mkForce {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 2222;
              };
            })
          ];
        };
        defaulted = mkEvaluations {
          publications.publisher = [
            (lib.mkDefault {
              backupDestinations.archive = {
                host = "discarded.example.test";
                port = 22;
              };
            })
          ];
        };
      in
      {
        shared = evaluations.registry.validate;
        local = succeeds evaluations.participants.publisher.config.registry.backupDestinations;
        defaultedNames = builtins.attrNames defaulted.registry.combined.backupDestinations;
      };
    expected = {
      shared = true;
      local = false;
      defaultedNames = [ ];
    };
  };

  testStaticLocalConditionsPreserveListOrder = {
    expr =
      map
        (
          enable:
          let
            evaluations = mkEvaluations {
              central = [
                {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                    paths = [ "/central" ];
                  };
                }
              ];
              participantModules.publisher = [ { services.prometheus.enable = enable; } ];
              publications.publisher = [
                (lib.mkIf evaluations.participants.publisher.config.services.prometheus.enable (
                  lib.mkMerge [
                    { backupDestinations.archive.paths = lib.mkBefore [ "/before" ]; }
                    { backupDestinations.archive.paths = lib.mkAfter [ "/after" ]; }
                    (lib.mkIf false (throw "A disabled contribution was forced."))
                    { backupDestinations.archive.port = lib.mkIf false "invalid disabled port"; }
                  ]
                ))
              ];
            };
          in
          {
            paths = evaluations.registry.combined.backupDestinations.archive.paths;
            matchesDirect = evaluations.registry.combined == evaluations.direct;
            inherit (evaluations.registry) validate;
          }
        )
        [
          false
          true
        ];
    expected =
      map
        (paths: {
          inherit paths;
          matchesDirect = true;
          validate = true;
        })
        [
          [ "/central" ]
          [
            "/before"
            "/central"
            "/after"
          ]
        ];
  };

  testStaticRootPropertiesExcludeWiringInsideMergedFragments = {
    expr =
      map
        (
          property:
          let
            evaluations = mkEvaluations {
              wiringProperty = property;
              publications.publisher = [
                (property (
                  lib.mkMerge [
                    { settings = { inherit schemaModules; }; }
                    { backupDestinations.archive.host = "archive.example.test"; }
                    { backupDestinations.archive.port = 2222; }
                  ]
                ))
              ];
            };
          in
          {
            endpoint = evaluations.registry.combined.backupDestinations.archive.endpoint;
            localEndpoint =
              evaluations.participants.publisher.config.registry.backupDestinations.archive.endpoint;
            inherit (evaluations.registry) validate;
          }
        )
        [
          lib.mkDefault
          lib.mkForce
          (lib.mkOverride 20)
        ];
    expected = lib.replicate 3 {
      endpoint = "archive.example.test:2222";
      localEndpoint = "archive.example.test:2222";
      validate = true;
    };
  };

  testStaticDefaultsAndExplicitListsMatchDirectEvaluation = {
    expr =
      map
        (
          paths:
          let
            evaluations = mkEvaluations {
              central = [
                {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                  };
                }
              ];
              publications = {
                first = [ { backupDestinations.archive = paths; } ];
                second = [ { backupDestinations.archive = { }; } ];
                third = [ { backupDestinations.archive = { }; } ];
              };
            };
          in
          {
            paths = evaluations.registry.combined.backupDestinations.archive.paths;
            matchesDirect = evaluations.registry.combined == evaluations.direct;
            inherit (evaluations.registry) validate;
          }
        )
        [
          { }
          { paths = [ ]; }
          { paths = [ "/explicit" ]; }
        ];
    expected =
      map
        (paths: {
          inherit paths;
          matchesDirect = true;
          validate = true;
        })
        [
          [ "/srv/default" ]
          [ ]
          [ "/explicit" ]
        ];
  };

  testStaticScalarAndReadOnlyConflictsMatchDirect = {
    expr =
      map
        (
          contribution:
          let
            evaluations = mkEvaluations {
              central = [
                {
                  backupDestinations.archive = {
                    host = "archive.example.test";
                    port = 2222;
                  };
                }
              ];
              publications.publisher = [ { backupDestinations.archive = contribution; } ];
            };
          in
          {
            combined = succeeds evaluations.registry.combined;
            direct = succeeds evaluations.direct;
            validate = succeeds evaluations.registry.validate;
          }
        )
        [
          { host = "archive.example.test"; }
          { host = "conflict.example.test"; }
          { endpoint = "replacement.example.test:22"; }
        ];
    expected =
      map
        (success: {
          combined = success;
          direct = success;
          validate = success;
        })
        [
          true
          false
          false
        ];
  };

  testStaticNestedPrioritiesAndOrderingMatchDirectEvaluation = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            {
              backupDestinations.archive = {
                host = lib.mkDefault "default.example.test";
                port = 2222;
                paths = lib.mkDefault [ "/discarded" ];
              };
            }
          ];
          publications = {
            first = [
              (lib.mkMerge [
                {
                  backupDestinations.archive = {
                    host = lib.mkForce "forced.example.test";
                    paths = lib.mkAfter [ "/last" ];
                  };
                }
                { backupDestinations.archive.paths = lib.mkOrder 750 [ "/numeric" ]; }
              ])
            ];
            second = [
              {
                backupDestinations.archive = {
                  host = lib.mkOverride 40 "selected.example.test";
                  paths = lib.mkBefore [ "/first" ];
                };
              }
            ];
            third = [ { backupDestinations.archive.paths = [ "/ordinary" ]; } ];
          };
        };
      in
      {
        host = evaluations.registry.combined.backupDestinations.archive.host;
        paths = evaluations.registry.combined.backupDestinations.archive.paths;
        matchesDirect = evaluations.registry.combined == evaluations.direct;
        inherit (evaluations.registry) validate;
      };
    expected = {
      host = "selected.example.test";
      paths = [
        "/first"
        "/numeric"
        "/ordinary"
        "/last"
      ];
      matchesDirect = true;
      validate = true;
    };
  };

  testStaticParticipantsCompletePartialRecords = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [ { backupDestinations.archive.host = "archive.example.test"; } ];
          publications = {
            transport = [
              {
                backupDestinations.archive.port =
                  evaluations.participants.transport.config.services.prometheus.port;
              }
            ];
            paths = [ { backupDestinations.archive.paths = [ "/documents" ]; } ];
          };
          participantModules.transport = [ { services.prometheus.port = 2222; } ];
        };
      in
      {
        inherit (evaluations.registry) combined validate;
        matchesDirect = evaluations.registry.combined == evaluations.direct;
        centralComplete = succeeds evaluations.registry.central;
        localComplete = succeeds evaluations.participants.transport.config.registry.backupDestinations.archive;
        localPort = evaluations.participants.transport.config.registry.backupDestinations.archive.port;
        sharedRead =
          evaluations.participants.paths.config.registry.combined.backupDestinations.archive.command;
      };
    expected = {
      combined.backupDestinations.archive = {
        host = "archive.example.test";
        port = 2222;
        paths = [ "/documents" ];
        endpoint = "archive.example.test:2222";
        command = "backup archive.example.test:2222";
      };
      matchesDirect = true;
      centralComplete = false;
      localComplete = false;
      localPort = 2222;
      sharedRead = "backup archive.example.test:2222";
      validate = true;
    };
  };

  testStaticWiringDoesNotSuppressDefaultContributions = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            (lib.mkDefault {
              backupDestinations.archive = {
                host = "archive.example.test";
                port = 2222;
              };
            })
          ];
          publications.reader = [ ];
        };
      in
      {
        inherit (evaluations.registry) combined validate;
        matchesDirect = evaluations.registry.combined == evaluations.direct;
        sharedRead =
          evaluations.participants.reader.config.registry.combined.backupDestinations.archive.endpoint;
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
      sharedRead = "archive.example.test:2222";
      validate = true;
    };
  };
}
//
  lib.mapAttrs'
    (
      name: value:
      lib.nameValuePair "testStatic${lib.replaceStrings [ "Publication" ] [ "Contribution" ] (lib.removePrefix "test" name)}" value
    )
    (
      import ./check-publication.nix {
        inherit lib;
        inherit (registryFlake.lib) mkRegistry;
        mkParticipant =
          {
            registry,
            schemaModules,
            publication,
          }:
          lib.nixosSystem {
            modules = [
              registryFlake.nixosModules.default
              {
                nixpkgs.hostPlatform = system;
                registry = {
                  settings = { inherit schemaModules; };
                  inherit (registry) central combined validate;
                };
              }
              { registry = publication; }
            ];
          };
      }
    )
