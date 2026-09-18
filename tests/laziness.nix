{ lib, mkRegistry }:
let
  mkCollectionEvaluations =
    collectionType:
    let
      schema = {
        options.settings = lib.mkOption {
          type = collectionType lib.types.str;
          default = { };
          description = "Shared settings with an unused failing entry.";
        };
      };
      central = {
        settings.domain = "example.test";
      };
      publication = {
        settings.unused = throw "Unused entry was forced.";
      };
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ schema ];
        centralModules = [ central ];
        participants.publisher = lib.evalModules {
          modules = [
            registry.module
            { registry = publication; }
          ];
        };
      };
      direct = lib.evalModules {
        modules = [
          schema
          central
          publication
        ];
      };
    in
    {
      inherit direct registry;
    };
in
{
  testCombinedDomainLeavesAnUnrelatedInvalidServiceUnused = {
    expr =
      let
        registry = mkRegistry {
          inherit lib;
          schemaModules = [ ../examples/plain-nix/service-schema.nix ];
          centralModules = [ { domain = "example.test"; } ];
          participants.publisher = lib.evalModules {
            modules = [
              registry.module
              {
                registry.services.api = {
                  host = "api.example.test";
                  port = "invalid port";
                };
              }
            ];
          };
        };
      in
      {
        domain = registry.combined.domain;
        invalidReadSucceeds = (builtins.tryEval registry.combined.services.api.port).success;
      };
    expected = {
      domain = "example.test";
      invalidReadSucceeds = false;
    };
  };

  testLazyCollectionLeavesAnUnrelatedThrowUnused = {
    expr =
      let
        evaluations = mkCollectionEvaluations lib.types.lazyAttrsOf;
        settings = evaluations.registry.combined.settings;
      in
      {
        inherit (settings) domain;
        matchesDirect = settings.domain == evaluations.direct.config.settings.domain;
        invalidReadSucceeds = (builtins.tryEval settings.unused).success;
      };
    expected = {
      domain = "example.test";
      matchesDirect = true;
      invalidReadSucceeds = false;
    };
  };

  testStrictCollectionForcesAnUnrelatedThrowLikeDirectEvaluation = {
    expr =
      let
        evaluations = mkCollectionEvaluations lib.types.attrsOf;
      in
      {
        combinedReadSucceeds = (builtins.tryEval evaluations.registry.combined.settings.domain).success;
        directReadSucceeds = (builtins.tryEval evaluations.direct.config.settings.domain).success;
      };
    expected = {
      combinedReadSucceeds = false;
      directReadSucceeds = false;
    };
  };
}
