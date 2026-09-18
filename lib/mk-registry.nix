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

  central = mkEvaluation [ ];
  combined = mkEvaluation contributions;

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
      inherit (checkRoot evaluation) config;
    in
    builtins.mapAttrs (name: _: config.${name}) schemaOptions;

  checkRoot =
    evaluation:
    if evaluation._module.freeformType != null then
      throw "nixos-registry: unrestricted freeform roots are unsupported; declare options in schemaModules."
    else
      evaluation;

  schemaOptions = removeAttrs schema.options [ "_module" ];

  schema = lib.evalModules {
    inherit specialArgs;
    modules = schemaModules;
  };

  contributions = lib.pipe participants [
    (lib.mapAttrsToList (
      name: participant:
      let
        option = getContributionOption name participant;
      in
      map (
        definition:
        let
          value = checkPublication name definition.file schemaOptions [ "registry" ] definition.value;
          # Root ordering is separate from the contribution's override priority.
          ordered = if definition ? priority then lib.mkOrder definition.priority value else value;
        in
        {
          _file = "participant ${name}: ${definition.file}";
          config.registry = lib.mkOverride option.highestPrio ordered;
        }
      ) option.definitionsWithLocations
    ))
    lib.concatLists
  ];

  getContributionOption =
    name: participant:
    builtins.addErrorContext "while collecting registry data from participant `${name}':" (
      let
        option = participant.options.registry;
      in
      if !(participant ? options.registry) then
        throw (
          "nixos-registry: participant `${name}` is missing options.registry; "
          + "import the generated registry.module."
        )
      else if
        !(lib.isOption option)
        || option.type.name or null != "submodule"
        || !(option._nixosRegistry or false)
        || !(option ? definitionsWithLocations && option ? highestPrio)
      then
        throw (
          "nixos-registry: participant `${name}` has an incompatible options.registry; "
          + "import the generated registry.module."
        )
      else
        option
    );

  module = {
    options.registry =
      lib.mkOption {
        type = lib.types.submoduleWith {
          inherit specialArgs;
          modules = schemaModules;
          shorthandOnlyDefinesConfig = true;
        };
        default = { };
        description = "This participant's contribution to the shared registry.";
      }
      // {
        # Identify the generated interface without forcing local values.
        _nixosRegistry = true;
      };
  };
in
builtins.seq (checkRoot schema) {
  inherit module;

  central = mkView central;
  combined = mkView combined;
  validate = builtins.deepSeq (checkRoot combined).config true;
}
