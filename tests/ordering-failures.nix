{
  lib,
  mkRegistry,
  source,
  order,
  view,
}:
let
  mkEvaluations = import ./fixtures/evaluate-properties.nix { inherit lib mkRegistry; };
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
