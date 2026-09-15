{ lib, schemaGraph }:
let
  wrapModule =
    args: source:
    let
      module = loadModule args source;
      metadata = builtins.intersectAttrs {
        _class = null;
        _file = null;
        disabledModules = null;
        key = null;
      } module;
      config =
        if module ? config || module ? options then
          module.config or { }
        else
          removeAttrs module (
            builtins.attrNames metadata
            ++ [
              "freeformType"
              "imports"
              "require"
            ]
          );
      unsupported = removeAttrs module (
        builtins.attrNames metadata
        ++ [
          "config"
          "freeformType"
          "imports"
          "meta"
          "options"
        ]
      );
    in
    if module ? key && builtins.hasAttr (toString module.key) schemaKeys then
      # The shared evaluation already imports these declarations and defaults.
      { }
    else if (module ? config || module ? options) && unsupported != { } then
      throw (
        "nixos-registry: central module `${module._file or "<unknown-file>"}` "
        + "has unsupported attribute `${builtins.head (builtins.attrNames unsupported)}`. "
        + "Definitions belong under config when config or options is present."
      )
    else
      metadata
      // {
        imports = map (wrapModule args) (module.require or [ ] ++ module.imports or [ ]);
        config.registry = lib.mkMerge (
          # Import-only modules must not override contribution-wide defaults.
          lib.optional (config != { }) config
          ++ lib.optional ((module ? config || module ? options) && module ? meta) { meta = module.meta; }
          ++ lib.optional (module ? freeformType) { _module.freeformType = module.freeformType; }
        );
      }
      // lib.optionalAttrs (module.options or { } != { }) {
        # Type extensions cannot repeat the declared option's description.
        options.registry = lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [ (metadata // { inherit (module) options; }) ];
          };
        };
      };

  schemaKeys = lib.genAttrs (collectSchemaKeys schemaGraph) (_: true);

  collectSchemaKeys =
    modules:
    lib.concatMap (
      module: if module.disabled then [ ] else [ module.key ] ++ collectSchemaKeys module.imports
    ) modules;

  loadModule =
    args: module:
    if lib.isFunction module then
      let
        moduleArgs = builtins.mapAttrs (name: _: args.${name} or args.config._module.args.${name}) (
          lib.functionArgs module
        );
      in
      loadModule args (module (args // moduleArgs))
    else if lib.types.path.check module then
      {
        _file = toString module;
        key = toString module;
      }
      // loadModule args (import module)
    else if module._type or null == "override" || module._type or null == "if" then
      { config = module; }
    else
      module;

in
wrapModule
