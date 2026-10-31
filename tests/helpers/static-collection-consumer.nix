# A static consumer whose contribution reads the combined collection it
# contributes to; the collection type decides whether the read recurses.
{ lib, mkStaticConsumer }:
collectionType:
mkStaticConsumer {
  schemaModules = [
    {
      options.endpoints = lib.mkOption {
        type = collectionType lib.types.str;
        default = { };
        description = "Shared domain and service endpoint.";
      };
    }
  ];
  centralModules = [ { endpoints.domain = "example.test"; } ];
  nodeModules.publisher = [
    ({ registry, ... }: {
      registry.endpoints.api = "api.${registry.combined.endpoints.domain}:8443";
    })
  ];
}
