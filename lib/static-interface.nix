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
in
{
  inherit checkSchema reservedNames;
  selectContribution =
    schemaOptions: value: checkSchema schemaOptions (removeAttrs value reservedNames);
}
