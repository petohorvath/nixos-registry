{ lib, mkRegistry }:
let
  mkServiceRegistry =
    service:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
        centralModules = [ { domain = "example.test"; } ];
        participants."unused service" = lib.evalModules {
          modules = [
            registry.module
            { registry.services.api = service; }
          ];
        };
      };
    in
    registry;
in
{
  testMalformedParticipantsLeaveCentralReadsIndependent = {
    expr =
      map
        (
          participant:
          let
            registry = mkRegistry {
              inherit lib;
              schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
              centralModules = [ { domain = "example.test"; } ];
              participants."invalid participant" = participant;
            };
          in
          {
            centralDomain = registry.central.domain;
            combinedKeys = builtins.attrNames registry.combined;
            validates = (builtins.tryEval registry.validate).success;
          }
        )
        [
          null
          "not an evaluation"
          [ ]
          { config.registry = { }; }
          (lib.evalModules { modules = [ ]; })
          (lib.evalModules {
            modules = [
              {
                options.registry.unrelated = lib.mkOption {
                  type = lib.types.str;
                  default = "a namespace instead of the generated option";
                  description = "An incompatible registry namespace.";
                };
              }
            ];
          })
        ];
    expected = lib.replicate 6 {
      centralDomain = "example.test";
      combinedKeys = [
        "domain"
        "services"
      ];
      validates = false;
    };
  };

  testExplicitDefinitionOriginsPreservePrioritiesAndOrdering = {
    expr =
      let
        mkEvaluations = import ../fixtures/evaluate-properties.nix { inherit lib mkRegistry; };
        evaluations = mkEvaluations {
          central = [ { backupPaths = lib.mkDefault [ "/discarded" ]; } ];
          publications.publisher = [
            {
              backupPaths = lib.mkDefinition {
                file = "/modules/before.nix";
                value = lib.mkBefore [ "/before" ];
              };
            }
            {
              backupPaths = lib.mkDefinition {
                file = "/modules/after.nix";
                value = lib.mkAfter [ "/after" ];
              };
            }
            {
              backupPaths = lib.mkIf false (
                lib.mkDefinition {
                  file = "/modules/disabled.nix";
                  value = throw "A disabled explicit definition was forced.";
                }
              );
            }
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
        "/before"
        "/after"
      ];
      matchesDirect = true;
      validate = true;
    };
  };

  testValidationTreatsAssertionsAsOrdinaryData = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          participants = { };
          schemaModules = [
            {
              options.assertions = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      assertion = lib.mkOption {
                        type = lib.types.bool;
                        description = "A stored assertion result.";
                      };
                      message = lib.mkOption {
                        type = lib.types.str;
                        description = "A stored assertion message.";
                      };
                    };
                  }
                );
                default = [ ];
                description = "Caller-owned assertion data.";
              };
            }
          ];
          centralModules = [
            {
              assertions = [
                {
                  assertion = false;
                  message = "Registry validation leaves assertion data uninterpreted.";
                }
              ];
            }
          ];
        };
      in
      {
        inherit (registry) validate;
        inherit (builtins.head registry.combined.assertions) assertion;
      };
    expected = {
      assertion = false;
      validate = true;
    };
  };

  testValidationRejectsUnusedSchemaErrors = {
    expr =
      builtins.mapAttrs
        (
          _: service:
          let
            registry = mkServiceRegistry service;
          in
          {
            domain = registry.combined.domain;
            validates = (builtins.tryEval registry.validate).success;
          }
        )
        {
          invalidType = {
            host = "api.example.test";
            port = "invalid port";
          };
          missingRequired.host = "api.example.test";
          unknownOption = {
            host = "api.example.test";
            port = 443;
            undeclared = true;
          };
          readOnly = {
            host = "api.example.test";
            port = 443;
            endpoint = "replacement.example.test:443";
          };
        };
    expected = {
      invalidType = {
        domain = "example.test";
        validates = false;
      };
      missingRequired = {
        domain = "example.test";
        validates = false;
      };
      unknownOption = {
        domain = "example.test";
        validates = false;
      };
      readOnly = {
        domain = "example.test";
        validates = false;
      };
    };
  };
}
