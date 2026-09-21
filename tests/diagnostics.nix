{
  lib,
  mkRegistry,
  nixpkgs,
  staticModule,
  flakeModule,
  flakeParts,
  system,
  useStaticModule ? false,
  serviceSchema ? ../examples/plain-nix/service-schema.nix,
}:
let
  mkProjectRegistry =
    modules:
    (flakeParts.lib.mkFlake { inputs.self.outPath = ../.; } (
      { config, ... }: {
        imports = [ flakeModule ] ++ modules;
        systems = [ ];
        flake.lib.registry = config.registry;
      }
    )).lib.registry;

  duplicateProjectSettings =
    settings:
    mkProjectRegistry [
      {
        _file = "/modules/first-project.nix";
        registry.settings = settings;
      }
      {
        _file = "/modules/second-project.nix";
        registry.settings = settings;
      }
    ];

  mkStaticNode =
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
        inherit (settings) schemaModules;
        centralModules = [ { domain = "example.test"; } ];
        nodes = lib.mapAttrs (
          _: modules:
          if useStaticModule then
            mkStaticNode settings registry modules
          else
            lib.evalModules {
              modules = [ registry.module ] ++ modules;
            }
        ) publications;
      };
      settings.schemaModules = [
        serviceSchema
        {
          options.backupPaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Ordered backup paths.";
          };
        }
      ];
    in
    registry.validate;
in
{
  flakeStaticInvalidPort =
    ((import ./fixtures/static-flake-consumer.nix { inherit flakeParts nixpkgs system; }) {
      schemaModules = [ serviceSchema ];
      centralModules = [ { domain = "example.test"; } ];
      nodeModules."static service publisher" = [ ./fixtures/invalid-service.nix ];
    }).checks.${system}.registry.drvPath;

  flakeMissingSchema =
    (mkProjectRegistry [
      {
        registry.settings.nodes = { };
      }
    ]).validate;

  flakeMissingNodes =
    (mkProjectRegistry [
      {
        registry.settings.schemaModules = [ ];
      }
    ]).validate;

  flakeDuplicateNode =
    (duplicateProjectSettings {
      schemaModules = [ ];
      nodes."duplicate node" = { };
    }).validate;

  flakeDuplicateArgument =
    (duplicateProjectSettings {
      specialArgs.schemaLabel = "shared schema";
    }).settings.specialArgs.schemaLabel;

  flakeCentralConflict =
    (mkProjectRegistry [
      {
        _file = "/modules/first-project.nix";
        registry.settings = {
          schemaModules = [ serviceSchema ];
          nodes = { };
          centralModules = [ { domain = "first.example.test"; } ];
        };
      }
      {
        _file = "/modules/second-project.nix";
        registry.settings.centralModules = [ { domain = "second.example.test"; } ];
      }
    ]).validate;

  staticInvalidPort =
    let
      settings.schemaModules = [ serviceSchema ];
      registry = mkRegistry (
        settings
        // {
          inherit lib;
          centralModules = [ { domain = "example.test"; } ];
          nodes."static service publisher" = mkStaticNode settings registry [
            ./fixtures/invalid-service.nix
          ];
        }
      );
    in
    {
      shared = registry.validate;
      local =
        (mkStaticNode settings registry [ ./fixtures/invalid-service.nix ])
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
          nodes."colliding static node" = mkStaticNode settings registry [ ];
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
      nodes."handwritten contribution root" = lib.evalModules {
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
      nodes."unrelated registry option" = lib.evalModules {
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
      nodes."missing publication interface" = lib.evalModules {
        modules = [ ];
      };
    }).validate;
}
