/*
  Aggregates central declarations and named participant contributions using
  the caller's module library and relative shared schema.
*/
{
  lib,
  schemaModules,
  participants,
  centralModules ? [ ],
  specialArgs ? { },
}:
let
  central = lib.evalModules {
    inherit specialArgs;
    modules = schemaModules ++ centralModules;
  };

  combined = lib.evalModules {
    inherit specialArgs;
    modules = schemaModules ++ centralModules ++ contributions;
  };

  contributions = lib.pipe participants [
    (lib.mapAttrsToList (
      name: participant:
      map (definition: {
        _file = "participant ${name}: ${definition.file}";
        config = definition.value;
      }) participant.options.registry.definitionsWithLocations
    ))
    lib.concatLists
  ];
in
{
  module = {
    options.registry = lib.mkOption {
      type = lib.types.submoduleWith {
        inherit specialArgs;
        modules = schemaModules;
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "This participant's contribution to the shared registry.";
    };
  };

  central = central.config;
  combined = combined.config;
  validate = builtins.deepSeq combined.config true;
}
