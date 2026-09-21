# Mutually dependent publications recurse even with a lazy collection type.
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib;
    schemaModules = [
      {
        options.services = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.str;
          default = { };
          description = "Named service endpoints.";
        };
      }
    ];
    nodes =
      lib.mapAttrs
        (
          name: peer:
          lib.evalModules {
            specialArgs = { inherit registry; };
            modules = [
              registry.module
              ({ registry, ... }: { registry.services.${name} = registry.combined.services.${peer}; })
            ];
          }
        )
        {
          east = "west";
          west = "east";
        };
  };
in
{
  inherit (registry) combined validate;
}
