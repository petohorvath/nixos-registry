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
  checkPublication = import ./check-publication.nix { inherit lib; };

  checkRoot =
    evaluation:
    if evaluation._module.freeformType != null then
      throw "nixos-registry: unrestricted freeform roots are unsupported; declare options in schemaModules."
    else
      evaluation;

  mkView =
    evaluation:
    let
      config = (checkRoot evaluation).config;
    in
    builtins.mapAttrs (name: _: config.${name}) schemaOptions;

  schemaOptions = removeAttrs schema.options [ "_module" ];

  schema = lib.evalModules {
    inherit specialArgs;
    modules = schemaModules;
  };

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
        config = checkPublication schemaOptions [ "registry" ] definition.value;
      }) participant.options.registry.definitionsWithLocations
    ))
    lib.concatLists
  ];
in
builtins.seq (checkRoot schema) {
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

  central = mkView central;
  combined = mkView combined;
  validate = builtins.deepSeq (checkRoot combined).config true;
}
