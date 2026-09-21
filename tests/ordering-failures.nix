{
  lib,
  mkRegistry,
  source,
  order,
  view,
  useStaticModule ? false,
  nixpkgs ? null,
  system ? null,
  staticModule ? null,
}:
let
  mkEvaluations = import ./fixtures/evaluate-properties.nix (
    {
      inherit lib mkRegistry;
    }
    // lib.optionalAttrs useStaticModule {
      mkParticipant =
        {
          registry,
          schemaModules,
          definitions,
        }:
        nixpkgs.lib.nixosSystem {
          modules = [
            staticModule
            {
              nixpkgs.hostPlatform = system;
              registry = {
                settings = { inherit schemaModules; };
                inherit (registry) central combined validate;
              };
            }
          ]
          ++ map (registry: { inherit registry; }) definitions;
        };
    }
  );
  mkOrderedDefinition =
    {
      before = lib.mkBefore;
      after = lib.mkAfter;
      explicit = lib.mkOrder 750;
    }
    .${order};
  ordered = mkOrderedDefinition { backupPaths = [ "/ordered" ]; };
  evaluations = mkEvaluations (
    if source == "central" then
      {
        central = [ ordered ];
        publications.publisher = [ { backupPaths = [ "/participant" ]; } ];
      }
    else
      {
        central = [ { backupPaths = [ "/central" ]; } ];
        publications.publisher = [ ordered ];
      }
  );
in
{
  result = evaluations.${view};
}
