{ lib }:
nodeName: sourceFile:
let
  checkOptions =
    {
      options,
      path,
      freeformType ? null,
      ...
    }:
    mapProperties (
      file: value:
      let
        freeform = checkValue freeformType path file (removeAttrs value (builtins.attrNames options));
      in
      if builtins.isAttrs value then
        builtins.mapAttrs (
          name: definition:
          if name == "_module" then
            addPublicationContext file (
              throw "nixos-registry: publication at `${lib.showOption path}` changes module controls."
            )
          else if !(options ? ${name}) then
            if freeformType == null then definition else freeform.${name}
          else if lib.isOption options.${name} then
            checkValue options.${name}.type (path ++ [ name ]) file definition
          else
            checkOptions {
              options = options.${name};
              path = path ++ [ name ];
            } file definition
        ) value
      else
        value
    );

  checkValue =
    type: path:
    mapProperties (
      file: value:
      if type.name == "submodule" then
        let
          schema = {
            options = type.getSubOptions path;
            inherit path;
            freeformType = type.nestedTypes.freeformType or null;
            # Schema identities can depend on the submodule's real name and option path.
            evaluate =
              args:
              lib.evalModules {
                inherit (type.functor.payload) class specialArgs;
                prefix = args._prefix;
                modules = [
                  { _module.args.name = lib.mkOptionDefault (args.name or args.config._module.args.name); }
                ]
                ++ type.getSubModules;
              };
          };
        in
        if builtins.isAttrs value && type.functor.payload.shorthandOnlyDefinesConfig then
          checkOptions schema file value
        else
          checkModule schema file value
      else if
        builtins.elem type.name [
          "attrsOf"
          "lazyAttrsOf"
        ]
        && builtins.isAttrs value
      then
        builtins.mapAttrs (name: checkValue type.nestedTypes.elemType (path ++ [ name ]) file) value
      else if type.name == "listOf" && builtins.isList value then
        map (checkValue type.nestedTypes.elemType path file) value
      else if type.name == "functionTo" && lib.isFunction value then
        lib.setFunctionArgs (
          argument: checkValue type.nestedTypes.elemType (path ++ [ "<function body>" ]) file (value argument)
        ) (lib.functionArgs value)
      else if type.name == "attrTag" then
        checkOptions {
          options = type.nestedTypes;
          inherit path;
        } file value
      else if
        builtins.elem type.name [
          "nullOr"
          "unique"
        ]
        && value != null
      then
        checkValue type.nestedTypes.elemType path file value
      else if type.name == "either" then
        checkValue (
          if type.nestedTypes.left.check value then type.nestedTypes.left else type.nestedTypes.right
        ) path file value
      else if type.name == "coercedTo" && !(type.nestedTypes.coercedType.check value) then
        checkValue type.nestedTypes.finalType path file value
      else
        value
    );

  checkModule =
    schema: parentFile: value:
    let
      file = if lib.types.path.check value then toString value else value._file or parentFile;
    in
    addPublicationContext file (
      if lib.isFunction value then
        args:
        let
          # Retain arguments supplied through the submodule's _module.args.
          moduleArgs = builtins.mapAttrs (name: _: args.${name} or args.config._module.args.${name}) (
            lib.functionArgs value
          );
        in
        checkModule (schema // { context = args; }) file (value (args // moduleArgs))
      else if lib.types.path.check value then
        args:
        let
          checked = checkModule (schema // { context = args; }) file (import value);
        in
        {
          _file = "node ${nodeName}: ${toString value}";
          key = toString value;
        }
        // (if lib.isFunction checked then checked args else checked)
      else if !(builtins.isAttrs value) then
        value
      else if value.options or { } != { } then
        throw "nixos-registry: publication at `${lib.showOption schema.path}` declares options; use schemaModules."
      else if value.freeformType or null != null then
        throw "nixos-registry: publication at `${lib.showOption schema.path}` sets freeformType; use schemaModules."
      else if value.disabledModules or [ ] != [ ] && !(schema ? context) then
        args: checkModule (schema // { context = args; }) file value
      else
        let
          metadata = builtins.intersectAttrs {
            _class = null;
            _file = null;
            disabledModules = null;
            freeformType = null;
            imports = null;
            key = null;
            require = null;
          } value;
          checked =
            if value ? config || value ? options then
              value
              // {
                config = checkOptions schema file (value.config or { });
              }
              // lib.optionalAttrs (value ? meta) {
                inherit (checkOptions schema file { inherit (value) meta; }) meta;
              }
            else
              checkOptions schema file (removeAttrs value (builtins.attrNames metadata)) // metadata;
        in
        checked
        // lib.optionalAttrs (value.disabledModules or [ ] != [ ]) {
          disabledModules = checkDisabledModules schema file value.disabledModules;
        }
        // lib.optionalAttrs (value ? _file) {
          _file = "node ${nodeName}: ${toString value._file}";
        }
        // lib.optionalAttrs (value ? imports) {
          imports = map (checkModule schema file) value.imports;
        }
        // lib.optionalAttrs (value ? require) {
          require = map (checkModule schema file) value.require;
        }
    );

  checkDisabledModules =
    schema: file: disabledModules:
    let
      evaluation = schema.evaluate schema.context;
      # Let Nix resolve relative paths and explicit keys before checking schema ownership.
      remaining = evaluation.extendModules { modules = [ { inherit disabledModules; } ]; };
      removedKeys = lib.subtractLists (getActiveModuleKeys remaining.graph) (
        getActiveModuleKeys evaluation.graph
      );
    in
    addPublicationContext file (
      if removedKeys == [ ] then
        disabledModules
      else
        throw (
          "nixos-registry: publication at `${lib.showOption schema.path}` "
          + "disables schema module `${builtins.head removedKeys}`; use schemaModules to control the shared schema."
        )
    );

  getActiveModuleKeys =
    graph:
    lib.pipe graph [
      (lib.filter (module: !module.disabled))
      (
        modules:
        builtins.genericClosure {
          startSet = modules;
          operator = module: lib.filter (imported: !imported.disabled) module.imports;
        }
      )
      (map (module: module.key))
    ];

  addPublicationContext =
    file: builtins.addErrorContext "while checking publication from node `${nodeName}' in `${file}':";

  # Keep checks beneath module properties lazy until those definitions are used.
  mapProperties =
    check: file: value:
    if
      builtins.isAttrs value
      && builtins.elem (value._type or null) [
        "if"
        "override"
        "order"
      ]
    then
      value // { content = mapProperties check file value.content; }
    else if builtins.isAttrs value && value._type or null == "merge" then
      value // { contents = map (mapProperties check file) value.contents; }
    else if builtins.isAttrs value && value._type or null == "definition" then
      value
      // {
        file = "node ${nodeName}: ${value.file}";
        value = mapProperties check value.file value.value;
      }
    else
      check file value;
in
options: path: checkOptions { inherit options path; } sourceFile
