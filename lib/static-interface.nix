{ lib }:
let
  reservedNames = [
    "settings"
    "central"
    "combined"
    "validate"
  ];
  checkSchema =
    schemaOptions: value:
    let
      collisions = lib.intersectLists reservedNames (builtins.attrNames schemaOptions);
      name = builtins.head collisions;
      declarations = lib.concatMap (option: option.declarations) (
        lib.collect lib.isOption schemaOptions.${name}
      );
    in
    if collisions == [ ] then
      value
    else
      throw (
        "nixos-registry: schema option `registry.${name}` conflicts with a reserved static interface name"
        + lib.optionalString (declarations != [ ]) " declared in ${lib.showFiles declarations}"
        + ". Rename the schema field or use the generated registry.module interface."
      );

  stripWiring =
    value:
    if
      builtins.elem (value._type or null) [
        "if"
        "override"
        "order"
      ]
    then
      value // { content = stripWiring value.content; }
    else if value._type or null == "merge" then
      value // { contents = map stripWiring value.contents; }
    else if value._type or null == "definition" then
      value // { value = stripWiring value.value; }
    else
      removeAttrs value reservedNames;

  isWiringOnly =
    value:
    # Surviving properties stay opaque until shared root priorities select them.
    removeAttrs value reservedNames == { } && lib.any (name: value ? ${name}) reservedNames;
in
{
  inherit checkSchema reservedNames;
  selectContributions =
    schemaOptions: definitions:
    checkSchema schemaOptions (
      lib.concatMap (
        definition:
        let
          value = stripWiring definition.value;
          # An ordered root must reach the caller's type, including its native failure.
          wiringOnly = !(definition ? priority) && isWiringOnly definition.value;
        in
        lib.optional (!wiringOnly) (definition // { inherit value; })
      ) definitions
    );
}
