/*
  Build a registry: shared configuration data formed from central definitions
  and node contributions under one schema. The caller supplies the module
  library, so the registry follows the caller's module-system selection.

  Arguments:
  - `lib`: the caller's Nixpkgs library, providing the module system.
  - `schemaModules`: modules declaring the shared options, relative to the
    `registry` option.
  - `nodes`: an attrset of evaluated configurations; each name identifies its
    node's contributions.
  - `centralModules`: modules defining shared values outside node
    contributions. Defaults to `[ ]`.
  - `moduleArgs`: arguments for schema and central modules. Defaults to
    `{ }`.

  Returns the registry: the arguments other than `lib`, with their defaults,
  plus `module` (the node module), `central` (central data), `combined`
  (combined data), and `valid` (`true` once all combined data evaluates).
*/
{
  lib,
  schemaModules,
  nodes,
  centralModules ? [ ],
  moduleArgs ? { },
}:
let
  schema = lib.evalModules {
    specialArgs = moduleArgs;
    modules = schemaModules;
  };

  checkRoot =
    evaluation:
    if evaluation._module.freeformType != null then
      throw "nixos-registry: unrestricted freeform roots are unsupported; declare options in schemaModules."
    else
      evaluation;

  schemaOptions = removeAttrs schema.options [ "_module" ];

  checkContribution = import ./check-contribution.nix { inherit lib; };
  wrapCentralModule = import ./wrap-central-module.nix {
    inherit lib;
    schemaGraph = schema.graph;
  };

  # The root that selects whole contributions in the shared evaluations.
  contributionRoot = {
    _file = toString ./mk-registry.nix;
    options.registry = lib.mkOption {
      type = lib.types.submoduleWith {
        specialArgs = moduleArgs;
        modules = schemaModules;
        shorthandOnlyDefinesConfig = true;
      };
      default = { };
      description = "A contribution to the shared registry.";
    };
  };

  getContributionOption =
    name: node:
    let
      option = node.options.registry;
    in
    if !(node ? options.registry) then
      throw "nixos-registry: node `${name}` is missing options.registry; import registry.module."
    else if
      !(lib.isOption option)
      || option.type.name or null != "submodule"
      || !(option._nixosRegistry or false)
      || !(option ? definitionsWithLocations && option ? highestPrio)
    then
      throw "nixos-registry: node `${name}` has an incompatible options.registry; import registry.module."
    else
      option;

  contributions = lib.pipe nodes [
    (lib.mapAttrsToList (
      name: node:
      let
        option = getContributionOption name node;
      in
      # Native module-system errors from the node's option lack its name.
      builtins.addErrorContext "while collecting registry data from node `${name}':" (
        map (
          definition:
          let
            value = checkContribution name definition.file schemaOptions [ "registry" ] definition.value;
            # Root ordering is separate from the contribution's override
            # priority.
            ordered = if definition ? priority then lib.mkOrder definition.priority value else value;
          in
          {
            _file = "node ${name}: ${definition.file}";
            config.registry = lib.mkOverride option.highestPrio ordered;
          }
        ) option.definitionsWithLocations
      )
    ))
    lib.concatLists
  ];

  evaluateContributions =
    contributionModules:
    lib.evalModules {
      specialArgs = moduleArgs;
      modules = [
        (
          args:
          let
            # Select whole contributions without demanding complete records.
            selected = lib.evalModules {
              specialArgs = moduleArgs;
              modules = [
                contributionRoot
              ]
              ++ map (wrapCentralModule args) centralModules
              ++ contributionModules;
            };
            option = selected.options.registry;
          in
          # Let the supplied root type accept the selected definition
          # properties.
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

  central = evaluateContributions [ ];
  combined = evaluateContributions contributions;

  registry = {
    inherit
      centralModules
      moduleArgs
      nodes
      schemaModules
      ;

    # The node module, with this registry as its `registry` argument.
    module = {
      _file = toString ./mk-registry.nix;
      imports = [ ../nixos/module.nix ];
      _module.args = { inherit registry; };
    };
    central = getSharedData central;
    combined = getSharedData combined;
    valid = builtins.deepSeq (checkRoot combined).config true;
  };

  getSharedData =
    evaluation:
    let
      inherit (checkRoot evaluation) config;
    in
    builtins.mapAttrs (name: _: config.${name}) schemaOptions;
in
builtins.seq (checkRoot schema) registry
