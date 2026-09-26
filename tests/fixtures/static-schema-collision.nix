{ lib, reservedName, ... }:
{
  options.${reservedName} = lib.mkOption {
    type = lib.types.str;
    default = "colliding schema field";
    description = ''
      A schema field colliding with the static registry interface.
    '';
  };
}
