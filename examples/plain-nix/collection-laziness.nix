# The same data references succeed or recurse depending on the collection type.
{ lib, mkRegistry }:
let
  mkExample =
    collectionType:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [
          {
            options.settings = lib.mkOption {
              type = collectionType lib.types.str;
              default = { };
              description = ''
                Shared domain and service endpoint.
              '';
            };
          }
        ];
        centralModules = [ { settings.domain = "example.test"; } ];
        nodes."API publisher" = lib.evalModules {
          specialArgs = { inherit registry; };
          modules = [
            registry.module
            (
              { registry, ... }:
              {
                registry.settings.endpoint = "api.${registry.combined.settings.domain}:8443";
              }
            )
          ];
        };
      };
    in
    {
      inherit (registry) combined validate;
    };
in
{
  strict = mkExample lib.types.attrsOf;
  lazy = mkExample lib.types.lazyAttrsOf;
}
