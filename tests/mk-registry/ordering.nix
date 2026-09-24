{ lib, mkRegistry }:
let
  mkEvaluations = import ../fixtures/evaluate-properties.nix { inherit lib mkRegistry; };
in
{
  testEqualListOrdersPreserveModuleAndFragmentOrder = {
    expr =
      let
        schema.options.backupPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Paths included in the backup.
          '';
        };
        definitions = [
          { backupPaths = lib.mkBefore [ "/first" ]; }
          (lib.mkMerge [
            { backupPaths = lib.mkBefore [ "/second" ]; }
            { backupPaths = lib.mkBefore [ "/third" ]; }
          ])
        ];
        centralModules = map (config: { inherit config; }) definitions;
        nodeModules = map (registry: { inherit registry; }) definitions;
        centralRegistry = mkRegistry {
          inherit centralModules lib;
          schemaModules = [ schema ];
          nodes = { };
        };
        nodeRegistry = mkRegistry {
          inherit lib;
          schemaModules = [ schema ];
          nodes.publisher = lib.evalModules {
            modules = [ nodeRegistry.module ] ++ nodeModules;
          };
        };
        directCentral = lib.evalModules { modules = [ schema ] ++ centralModules; };
        directNode = lib.evalModules {
          modules = [
            {
              options.registry = lib.mkOption {
                type = lib.types.submoduleWith {
                  modules = [ schema ];
                  shorthandOnlyDefinesConfig = true;
                };
                default = { };
                description = ''
                  The independent reference's typed contribution root.
                '';
              };
            }
          ]
          ++ nodeModules;
        };
      in
      {
        centralPaths = centralRegistry.combined.backupPaths;
        nodePaths = nodeRegistry.combined.backupPaths;
        centralMatchesDirect = centralRegistry.combined == directCentral.config;
        nodeMatchesDirect = nodeRegistry.combined == directNode.config.registry;
        valid = centralRegistry.validate && nodeRegistry.validate;
      };
    expected = {
      centralPaths = [
        "/second"
        "/third"
        "/first"
      ];
      nodePaths = [
        "/first"
        "/third"
        "/second"
      ];
      centralMatchesDirect = true;
      nodeMatchesDirect = true;
      valid = true;
    };
  };

  testNestedOrderingRespectsOverridePriorities = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            { backupPaths = lib.mkDefault (lib.mkBefore [ "/discarded" ]); }
          ];
          publications.publisher = [
            (lib.mkMerge [
              { backupPaths = lib.mkForce (lib.mkAfter [ "/last" ]); }
              { backupPaths = lib.mkForce (lib.mkOrder 100 [ "/first" ]); }
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
        "/first"
        "/last"
      ];
      matchesDirect = true;
      validate = true;
    };
  };

  testDiscardedRootOrderingDoesNotForceItsContent = {
    expr =
      map
        (
          source:
          let
            selected = lib.mkForce { backupPaths = [ "/selected" ]; };
            discarded = lib.mkBefore (throw "A discarded ordered contribution was forced.");
            evaluations = mkEvaluations {
              central = [ (if source == "central" then discarded else selected) ];
              publications.publisher = [ (if source == "node" then discarded else selected) ];
            };
          in
          {
            paths = evaluations.combined.backupPaths;
            matchesDirect = evaluations.combined == evaluations.direct;
            inherit (evaluations) validate;
          }
        )
        [
          "central"
          "node"
        ];
    expected = [
      {
        paths = [ "/selected" ];
        matchesDirect = true;
        validate = true;
      }
      {
        paths = [ "/selected" ];
        matchesDirect = true;
        validate = true;
      }
    ];
  };

  testNestedListOrderingMatchesDirectEvaluation = {
    expr =
      let
        evaluations = mkEvaluations {
          central = [
            { backupPaths = lib.mkAfter [ "/central-last" ]; }
            { backupPaths = lib.mkOrder 100 [ "/central-first" ]; }
          ];
          publications = {
            earlier = [ { backupPaths = lib.mkBefore [ "/before" ]; } ];
            later = [
              (lib.mkMerge [
                { backupPaths = [ "/ordinary" ]; }
                { backupPaths = lib.mkOrder 1250 [ "/explicit" ]; }
              ])
            ];
          };
        };
      in
      {
        paths = evaluations.combined.backupPaths;
        matchesDirect = evaluations.combined == evaluations.direct;
        inherit (evaluations) validate;
      };
    expected = {
      paths = [
        "/central-first"
        "/before"
        "/ordinary"
        "/explicit"
        "/central-last"
      ];
      matchesDirect = true;
      validate = true;
    };
  };
}
