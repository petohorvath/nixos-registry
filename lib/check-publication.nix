{ lib }:
let
  checkOptions =
    {
      options,
      path,
      freeformType ? null,
    }:
    mapProperties (
      value:
      let
        freeform = checkValue freeformType path (removeAttrs value (builtins.attrNames options));
      in
      if builtins.isAttrs value then
        builtins.mapAttrs (
          name: definition:
          if name == "_module" then
            throw "nixos-registry: publication at `${lib.showOption path}` changes module controls."
          else if !(options ? ${name}) then
            if freeformType == null then definition else freeform.${name}
          else if lib.isOption options.${name} then
            checkValue options.${name}.type (path ++ [ name ]) definition
          else
            checkOptions {
              options = options.${name};
              path = path ++ [ name ];
            } definition
        ) value
      else
        value
    );

  checkValue =
    type: path:
    mapProperties (
      value:
      if type.name == "submodule" then
        let
          schema = {
            options = type.getSubOptions path;
            inherit path;
            freeformType = type.nestedTypes.freeformType or null;
          };
        in
        if builtins.isAttrs value && type.functor.payload.shorthandOnlyDefinesConfig then
          checkOptions schema value
        else
          checkModule schema value
      else if
        builtins.elem type.name [
          "attrsOf"
          "lazyAttrsOf"
        ]
        && builtins.isAttrs value
      then
        builtins.mapAttrs (name: checkValue type.nestedTypes.elemType (path ++ [ name ])) value
      else if type.name == "listOf" && builtins.isList value then
        map (checkValue type.nestedTypes.elemType path) value
      else if type.name == "functionTo" && lib.isFunction value then
        lib.setFunctionArgs (
          argument: checkValue type.nestedTypes.elemType (path ++ [ "<function body>" ]) (value argument)
        ) (lib.functionArgs value)
      else if type.name == "attrTag" then
        checkOptions {
          options = type.nestedTypes;
          inherit path;
        } value
      else if
        builtins.elem type.name [
          "nullOr"
          "unique"
        ]
        && value != null
      then
        checkValue type.nestedTypes.elemType path value
      else if type.name == "either" then
        checkValue (
          if type.nestedTypes.left.check value then type.nestedTypes.left else type.nestedTypes.right
        ) path value
      else if type.name == "coercedTo" && !(type.nestedTypes.coercedType.check value) then
        checkValue type.nestedTypes.finalType path value
      else
        value
    );

  checkModule =
    schema: value:
    if lib.isFunction value then
      args:
      let
        # Retain arguments supplied through the submodule's _module.args.
        moduleArgs = builtins.mapAttrs (name: _: args.${name} or args.config._module.args.${name}) (
          lib.functionArgs value
        );
      in
      checkModule schema (value (args // moduleArgs))
    else if lib.types.path.check value then
      args:
      let
        checked = checkModule schema (import value);
      in
      {
        _file = toString value;
        key = toString value;
      }
      // (if lib.isFunction checked then checked args else checked)
    else if !(builtins.isAttrs value) then
      value
    else if value.options or { } != { } then
      throw "nixos-registry: publication at `${lib.showOption schema.path}` declares options; use schemaModules."
    else if value.freeformType or null != null then
      throw "nixos-registry: publication at `${lib.showOption schema.path}` sets freeformType; use schemaModules."
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
              config = checkOptions schema (value.config or { });
            }
            // lib.optionalAttrs (value ? meta) {
              meta = (checkOptions schema { meta = value.meta; }).meta;
            }
          else
            checkOptions schema (removeAttrs value (builtins.attrNames metadata)) // metadata;
      in
      checked
      // lib.optionalAttrs (value ? imports) {
        imports = map (checkModule schema) value.imports;
      }
      // lib.optionalAttrs (value ? require) {
        require = map (checkModule schema) value.require;
      };

  # Keep checks beneath module properties lazy until those definitions are used.
  mapProperties =
    check: value:
    if
      builtins.isAttrs value
      && builtins.elem (value._type or null) [
        "if"
        "override"
        "order"
      ]
    then
      value // { content = mapProperties check value.content; }
    else if builtins.isAttrs value && value._type or null == "merge" then
      value // { contents = map (mapProperties check) value.contents; }
    else
      check value;
in
options: path: checkOptions { inherit options path; }
