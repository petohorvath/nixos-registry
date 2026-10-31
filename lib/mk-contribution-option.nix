# Declare a contribution root typed by a registry's schema.
{ lib }:
{
  schemaModules,
  moduleArgs,
  description,
}:
lib.mkOption {
  type = lib.types.submoduleWith {
    modules = schemaModules;
    specialArgs = moduleArgs;
    shorthandOnlyDefinesConfig = true;
  };
  default = { };
  inherit description;
}
