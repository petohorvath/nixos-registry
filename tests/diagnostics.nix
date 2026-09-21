{
  lib,
  mkRegistry,
  nixpkgs,
  staticModule,
  system,
  serviceSchema ? ../examples/plain-nix/service-schema.nix,
}:
let
  mkStaticParticipant =
    settings: registry: modules:
    nixpkgs.lib.nixosSystem {
      modules = [
        staticModule
        {
          nixpkgs.hostPlatform = system;
          registry = {
            inherit settings;
            inherit (registry) central combined validate;
          };
        }
      ]
      ++ modules;
    };

  mkValidation =
    publications:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [
          serviceSchema
          {
            options.backupPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Ordered backup paths.";
            };
          }
        ];
        centralModules = [ { domain = "example.test"; } ];
        participants = lib.mapAttrs (
          _: modules:
          lib.evalModules {
            modules = [ registry.module ] ++ modules;
          }
        ) publications;
      };
    in
    registry.validate;
in
{
  staticInvalidPort =
    let
      settings.schemaModules = [ serviceSchema ];
      registry = mkRegistry (
        settings
        // {
          inherit lib;
          centralModules = [ { domain = "example.test"; } ];
          participants."static service publisher" = mkStaticParticipant settings registry [
            ./fixtures/invalid-service.nix
          ];
        }
      );
    in
    {
      shared = registry.validate;
      local =
        (mkStaticParticipant settings registry [ ./fixtures/invalid-service.nix ])
        .config.registry.services.api.port;
    };

  staticReservedSchema = lib.genAttrs [ "settings" "central" "combined" "validate" ] (
    reservedName:
    let
      settings = {
        schemaModules = [ ./fixtures/static-schema-collision.nix ];
        specialArgs = { inherit reservedName; };
      };
      registry = mkRegistry (
        settings
        // {
          inherit lib;
          participants."colliding static participant" = mkStaticParticipant settings registry [ ];
        }
      );
    in
    registry.validate
  );

  definitionSchemaDeclaration = mkValidation {
    "generated schema publisher" = [
      {
        _file = "/modules/generated-publication.nix";
        registry.services = lib.mkDefinition {
          file = "/generated/offending-publication.nix";
          value.api = _: {
            options.injected = lib.mkOption {
              type = lib.types.str;
              default = "undeclared shared option";
              description = "An option absent from the caller's schema.";
            };
          };
        };
      }
    ];
  };

  importedSchemaDeclaration = mkValidation {
    "importing schema publisher" = [
      {
        _file = "/modules/importing-publication.nix";
        registry.services.api = ./fixtures/shared-schema-data.nix;
      }
    ];
  };

  moduleControls = mkValidation {
    "module-control publisher" = [
      {
        _file = "/modules/publication-controls.nix";
        registry._module.check = false;
      }
    ];
  };

  schemaDeclaration = mkValidation {
    "schema-changing publisher" = [
      {
        _file = "/modules/schema-publication.nix";
        registry.services.api = _: {
          options.injected = lib.mkOption {
            type = lib.types.str;
            default = "undeclared shared option";
            description = "An option absent from the caller's schema.";
          };
        };
      }
    ];
  };

  conflictingInterface = mkValidation {
    "conflicting publication interface" = [
      {
        _file = "/modules/conflicting-interface.nix";
        # A type extension must not repeat the generated option's description.
        options.registry = lib.mkOption { type = lib.types.str; };
      }
    ];
  };

  missingRequired = mkValidation {
    "incomplete service publisher" = [
      { registry.services.api.host = "api.example.test"; }
    ];
  };

  unknownOption = mkValidation {
    "unknown service publisher" = [
      {
        _file = "/modules/unknown-service.nix";
        registry.services.api = {
          host = "api.example.test";
          port = 443;
          undeclared = true;
        };
      }
    ];
  };

  readOnly = mkValidation {
    "endpoint publisher" = [
      {
        _file = "/modules/endpoint.nix";
        registry.services.api = {
          host = "api.example.test";
          port = 443;
          endpoint = "replacement.example.test:443";
        };
      }
    ];
  };

  orderedList = mkValidation {
    "ordered path publisher" = [
      {
        _file = "/modules/ordered-paths.nix";
        registry = lib.mkMerge [
          { backupPaths = lib.mkBefore [ 42 ]; }
          { backupPaths = lib.mkAfter [ "/srv/documents" ]; }
        ];
      }
    ];
  };

  priorityConflict = mkValidation {
    "first address publisher" = [
      {
        _file = "/modules/first-address.nix";
        registry = lib.mkOverride 60 (
          lib.mkMerge [
            { services.api.host = "first.example.test"; }
            { services.api.port = 443; }
          ]
        );
      }
    ];
    "second address publisher" = [
      {
        _file = "/modules/second-address.nix";
        registry = lib.mkOverride 60 {
          domain = "example.test";
          services.api.host = "second.example.test";
        };
      }
    ];
  };

  invalidPort = mkValidation {
    "service publisher" = [ ./fixtures/invalid-service.nix ];
  };

  definitionOrigin = mkValidation {
    "generated service publisher" = [
      {
        registry.services.api = {
          host = "api.example.test";
          port = lib.mkDefinition {
            file = "/generated/service-port.nix";
            value = lib.mkOverride 70 "invalid port";
          };
        };
      }
    ];
  };

  submoduleOrigin = mkValidation {
    "imported service publisher" = [
      { registry.services.api = ./fixtures/invalid-service-record.nix; }
    ];
  };

  moduleOrigin = mkValidation {
    "module service publisher" = [
      {
        registry.services.api = _: {
          _file = "/modules/service-record.nix";
          host = "api.example.test";
          port = "invalid port";
        };
      }
    ];
  };

  unrelatedSubmodule =
    (mkRegistry {
      inherit lib;
      schemaModules = [ serviceSchema ];
      centralModules = [ { domain = "example.test"; } ];
      participants."handwritten contribution root" = lib.evalModules {
        modules = [
          {
            options.registry = lib.mkOption {
              type = lib.types.submodule {
                options.domain = lib.mkOption {
                  type = lib.types.str;
                  description = "An independently declared domain.";
                };
              };
              default = { };
              description = "A root declared without the generated module.";
            };
          }
        ];
      };
    }).validate;

  incompatibleOption =
    (mkRegistry {
      inherit lib;
      schemaModules = [ serviceSchema ];
      centralModules = [ { domain = "example.test"; } ];
      participants."unrelated registry option" = lib.evalModules {
        modules = [
          {
            options.registry = lib.mkOption {
              type = lib.types.str;
              default = "unrelated data";
              description = "An incompatible publication interface.";
            };
          }
        ];
      };
    }).validate;

  missingOption =
    (mkRegistry {
      inherit lib;
      schemaModules = [ serviceSchema ];
      centralModules = [ { domain = "example.test"; } ];
      participants."missing publication interface" = lib.evalModules {
        modules = [ ];
      };
    }).validate;
}
