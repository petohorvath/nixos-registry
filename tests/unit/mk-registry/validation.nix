{
  fixtures,
  helpers,
  lib,
  registryLib,
  ...
}:
let
  inherit (registryLib) mkRegistry;

  # A package whose attributes reach further data, as real packages reach
  # their package set.
  mkPackage =
    name: extraAttrs:
    {
      type = "derivation";
      inherit name;
      outPath = "/nix/store/00000000000000000000000000000000-${name}";
    }
    // extraAttrs;

  # Data without a bottom, standing in for a package set. Each level is a new
  # value, so `builtins.deepSeq` cannot stop at a repeated one.
  mkPackageSet = depth: { next = mkPackageSet (depth + 1); };

  # A registry whose schema holds a package by default and packages from
  # nodes.
  mkPackageRegistry =
    {
      defaultPackage,
      contributions ? { },
    }:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [
          {
            options = {
              tool = lib.mkOption {
                type = lib.types.package;
                default = defaultPackage;
                description = "A shared tool.";
              };
              tools = lib.mkOption {
                type = lib.types.attrsOf lib.types.package;
                default = { };
                description = "Named tools from nodes.";
              };
            };
          }
        ];
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
in
{
  testValidationTreatsPackagesAsLeaves = {
    expr =
      let
        registry = mkPackageRegistry {
          defaultPackage = mkPackage "default-tool" { pkgs = mkPackageSet 0; };
          contributions.publisher.tools.publisher = mkPackage "node-tool" {
            pkgs = mkPackageSet 0;
          };
        };
      in
      {
        inherit (registry) valid;
        inherit (registry.combined.tools.publisher) name;
      };
    expected = {
      valid = true;
      name = "node-tool";
    };
  };

  testValidationDoesNotInstantiatePackages = {
    expr =
      let
        uninstantiable.drvPath = throw "Validation instantiated a package.";
      in
      (mkPackageRegistry {
        defaultPackage = mkPackage "default-tool" uninstantiable;
        contributions.publisher.tools.publisher = mkPackage "node-tool" uninstantiable;
      }).valid;
    expected = true;
  };

  testValidationRejectsInvalidDataBesidePackages = {
    expr =
      (builtins.tryEval
        (mkPackageRegistry {
          defaultPackage = mkPackage "default-tool" { };
          contributions.publisher.tools.publisher = "not a package";
        }).valid
      ).success;
    expected = false;
  };

  testMalformedNodesLeaveCentralReadsIndependent = {
    expr =
      map
        (
          node:
          let
            registry = mkRegistry {
              inherit lib;
              schemaModules = [ fixtures.schemas.service ];
              centralModules = [ { domain = "example.test"; } ];
              nodes."invalid node" = node;
            };
          in
          {
            centralDomain = registry.central.domain;
            combinedKeys = builtins.attrNames registry.combined;
            validates = (builtins.tryEval registry.valid).success;
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
        mkEvaluations = helpers.evaluateProperties { };
        evaluations = mkEvaluations {
          central = [ { backupPaths = lib.mkDefault [ "/discarded" ]; } ];
          contributions.publisher = [
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
        inherit (evaluations) valid;
      };
    expected = {
      paths = [
        "/before"
        "/after"
      ];
      matchesDirect = true;
      valid = true;
    };
  };

  testValidationTreatsAssertionsAsOrdinaryData = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          nodes = { };
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
        inherit (registry) valid;
        inherit (builtins.head registry.combined.assertions) assertion;
      };
    expected = {
      assertion = false;
      valid = true;
    };
  };
}
