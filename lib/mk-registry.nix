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
  wrapCentralModule = import ./wrap-central-module.nix {
    inherit lib;
    schemaGraph = schema.graph;
  };

  checkRoot =
    evaluation:
    if evaluation._module.freeformType != null then
      throw "nixos-registry: unrestricted freeform roots are unsupported; declare options in schemaModules."
    else
      evaluation;

  mkEvaluation =
    contributions:
    lib.evalModules {
      inherit specialArgs;
      modules = [
        (
          args:
          let
            # Select whole contributions without demanding complete records.
            selected = lib.evalModules {
              inherit specialArgs;
              modules = [ module ] ++ map (wrapCentralModule args) centralModules ++ contributions;
            };
            option = selected.options.registry;
          in
          # Let the supplied root type accept the selected definition properties.
          builtins.seq option.value {
            imports =
              option.type.getSubModules
              # Root selection traverses modules in reverse declaration order.
              ++ map (definition: {
                _file = definition.file;
                config = definition.value;
              }) (lib.reverseList option.definitionsWithLocations);
          }
        )
      ];
    };

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

  central = mkEvaluation [ ];
  combined = mkEvaluation contributions;

  contributions = lib.pipe participants [
    (lib.mapAttrsToList (
      name: participant:
      map (
        definition:
        let
          value = checkPublication schemaOptions [ "registry" ] definition.value;
          # Root ordering is separate from the contribution's override priority.
          ordered = if definition ? priority then lib.mkOrder definition.priority value else value;
        in
        {
          _file = "participant ${name}: ${definition.file}";
          config.registry = lib.mkOverride participant.options.registry.highestPrio ordered;
        }
      ) participant.options.registry.definitionsWithLocations
    ))
    lib.concatLists
  ];

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
in
builtins.seq (checkRoot schema) {
  inherit module;

  central = mkView central;
  combined = mkView combined;
  validate = builtins.deepSeq (checkRoot combined).config true;
}
