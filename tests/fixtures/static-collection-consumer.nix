# A static consumer whose contribution reads the combined collection it
# contributes to; the collection type decides whether the read recurses.
{
  nixpkgs,
  flakeParts,
  system,
}:
collectionType:
let
  inherit (nixpkgs) lib;
in
import ./static-flake-consumer.nix { inherit flakeParts nixpkgs system; } {
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
    ({ config, ... }: {
      registry.endpoints.api = "api.${config.registry.combined.endpoints.domain}:8443";
    })
  ];
}
