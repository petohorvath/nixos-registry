{
  nixpkgs,
  flakeParts,
  system,
}:
let
  inherit (nixpkgs) lib;
  mkConsumer = import ./fixtures/static-flake-consumer.nix {
    inherit flakeParts nixpkgs system;
  };
  mkCollection =
    collectionType:
    mkConsumer {
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
      participantModules.publisher = [
        ({ config, ... }: {
          registry.endpoints.api = "api.${config.registry.combined.endpoints.domain}:8443";
        })
      ];
    };
in
{
  strict = mkCollection lib.types.attrsOf;
  lazy = mkCollection lib.types.lazyAttrsOf;
  valueCycle = mkConsumer {
    schemaModules = [
      {
        options.services = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.str;
          default = { };
          description = "Named service endpoints.";
        };
      }
    ];
    participantModules =
      lib.mapAttrs
        (name: peer: [
          ({ config, ... }: {
            registry.services.${name} = config.registry.combined.services.${peer};
          })
        ])
        {
          east = "west";
          west = "east";
        };
  };
  importCycle = mkConsumer {
    schemaModules = [ ../examples/plain-nix/service-schema.nix ];
    centralModules = [ { domain = "example.test"; } ];
    participantModules.publisher = [
      ({ config, ... }: {
        imports = lib.optional (config.registry.central.domain == "example.test") {
          registry.services.api = {
            host = "api.example.test";
            port = 8443;
          };
        };
      })
    ];
  };
}
