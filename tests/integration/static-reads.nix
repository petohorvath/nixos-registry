{
  nixpkgs,
  flakeParts,
  system,
}:
let
  inherit (nixpkgs) lib;
  mkConsumer = import ../fixtures/static-flake-consumer.nix {
    inherit flakeParts nixpkgs system;
  };
in
{
  testStaticCollectionStrictnessMatchesDirectEvaluation = {
    expr =
      lib.mapAttrs
        (
          _: collectionType:
          let
            schema = {
              options.endpoints = lib.mkOption {
                type = collectionType lib.types.str;
                default = { };
                description = ''
                  Shared endpoints with an unused failing value.
                '';
              };
            };
            central.endpoints.domain = "example.test";
            contribution.endpoints.unused = throw "The unused collection value was forced.";
            consumer = mkConsumer {
              schemaModules = [ schema ];
              centralModules = [ central ];
              nodeModules.publisher = [ { registry = contribution; } ];
            };
            direct = lib.evalModules {
              modules = [
                schema
                central
                contribution
              ];
            };
          in
          {
            combinedReadSucceeds = (builtins.tryEval consumer.lib.registry.combined.endpoints.domain).success;
            directReadSucceeds = (builtins.tryEval direct.config.endpoints.domain).success;
            validates = (builtins.tryEval consumer.lib.registry.validate).success;
          }
        )
        {
          strict = lib.types.attrsOf;
          lazy = lib.types.lazyAttrsOf;
        };
    expected = {
      strict = {
        combinedReadSucceeds = false;
        directReadSucceeds = false;
        validates = false;
      };
      lazy = {
        combinedReadSucceeds = true;
        directReadSucceeds = true;
        validates = false;
      };
    };
  };

  testStaticLazyCollectionSupportsSharedReadsWhileContributing = {
    expr =
      let
        consumer = (import ../static-recursion.nix { inherit flakeParts nixpkgs system; }).lazy;
      in
      {
        inherit (consumer.lib.registry) combined validate;
        localEndpoint = consumer.nixosConfigurations.publisher.config.registry.endpoints.api;
      };
    expected = {
      combined.endpoints = {
        domain = "example.test";
        api = "api.example.test:8443";
      };
      validate = true;
      localEndpoint = "api.example.test:8443";
    };
  };

  testStaticValidationTreatsAssertionsAsOrdinarySchemaData = {
    expr =
      let
        consumer = mkConsumer {
          schemaModules = [
            {
              options.assertions = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      assertion = lib.mkOption {
                        type = lib.types.bool;
                        description = ''
                          A stored assertion result.
                        '';
                      };
                      message = lib.mkOption {
                        type = lib.types.str;
                        description = ''
                          A stored assertion message.
                        '';
                      };
                    };
                  }
                );
                default = [ ];
                description = ''
                  Caller-owned assertion data.
                '';
              };
            }
          ];
          nodeModules.publisher = [
            {
              registry.assertions = [
                {
                  assertion = false;
                  message = "Registry assertion data is not executed as NixOS assertions.";
                }
              ];
            }
          ];
        };
      in
      {
        inherit (consumer.lib.registry) validate;
        inherit (builtins.head consumer.lib.registry.combined.assertions) assertion;
        checkEvaluates = (builtins.tryEval consumer.checks.${system}.registry.drvPath).success;
      };
    expected = {
      assertion = false;
      validate = true;
      checkEvaluates = true;
    };
  };

  testStaticUnrelatedReadsLeaveRegistryUnevaluated = {
    expr =
      let
        consumer = mkConsumer {
          schemaModules = throw "An unrelated read forced the schema.";
          centralModules = throw "An unrelated read forced central definitions.";
          nodeModules.reader = [ { networking.hostName = "independent"; } ];
          modules = [
            {
              registry.settings.nodes = lib.mkForce (throw "An unrelated read collected nodes.");
              flake.unrelated = "independent project value";
            }
          ];
        };
      in
      {
        projectValue = consumer.unrelated;
        nodeName = consumer.nixosConfigurations.reader.config.networking.hostName;
      };
    expected = {
      projectValue = "independent project value";
      nodeName = "independent";
    };
  };

  testStaticValidationAndFlakeChecksRejectUnusedSchemaErrors = {
    expr =
      lib.mapAttrs
        (
          _: service:
          let
            consumer = mkConsumer {
              schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
              centralModules = [ { domain = "example.test"; } ];
              nodeModules."unused service" = [ { registry.services.api = service; } ];
            };
          in
          {
            domain = consumer.lib.registry.combined.domain;
            validates = (builtins.tryEval consumer.lib.registry.validate).success;
            nodeValidates =
              (builtins.tryEval consumer.nixosConfigurations."unused service".config.registry.validate).success;
            checkEvaluates = (builtins.tryEval consumer.checks.${system}.registry.drvPath).success;
          }
        )
        {
          invalidType = {
            host = "api.example.test";
            port = "invalid port";
          };
          missingRequired.host = "api.example.test";
          unknownOption = {
            host = "api.example.test";
            port = 443;
            undeclared = true;
          };
          readOnly = {
            host = "api.example.test";
            port = 443;
            endpoint = "replacement.example.test:443";
          };
        };
    expected = lib.genAttrs [ "invalidType" "missingRequired" "unknownOption" "readOnly" ] (_: {
      domain = "example.test";
      validates = false;
      nodeValidates = false;
      checkEvaluates = false;
    });
  };

  testStaticFlakeChecksValidateCompletedRecords = {
    expr =
      let
        consumer = mkConsumer {
          schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
          centralModules = [
            {
              domain = "example.test";
              services.api.port = 8443;
            }
          ];
          nodeModules.publisher = [
            ({ config, ... }: {
              registry.services.api.host = "api.${config.registry.combined.domain}";
              environment.etc."api-endpoint".text = config.registry.combined.services.api.endpoint;
            })
          ];
        };
        node = consumer.nixosConfigurations.publisher.config;
      in
      {
        inherit (consumer.lib.registry) combined validate;
        centralPort = consumer.lib.registry.central.services.api.port;
        localHost = node.registry.services.api.host;
        localPortExists = (builtins.tryEval node.registry.services.api.port).success;
        centralHostExists = (builtins.tryEval consumer.lib.registry.central.services.api.host).success;
        endpoint = node.environment.etc."api-endpoint".text;
        nodeValidates = node.registry.validate;
        checkEvaluates = (builtins.tryEval consumer.checks.${system}.registry.drvPath).success;
      };
    expected = {
      combined = {
        domain = "example.test";
        services.api = {
          host = "api.example.test";
          port = 8443;
          endpoint = "api.example.test:8443";
        };
      };
      validate = true;
      centralPort = 8443;
      localHost = "api.example.test";
      localPortExists = false;
      centralHostExists = false;
      endpoint = "api.example.test:8443";
      nodeValidates = true;
      checkEvaluates = true;
    };
  };

  testStaticCentralReadsAndResultShapeLeaveNodesUnused = {
    expr =
      let
        consumer = mkConsumer {
          schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
          centralModules = [ { domain = "example.test"; } ];
          nodeModules.reader = [
            ({ config, ... }: {
              registry.services.api.host = "api.${config.registry.central.domain}";
            })
          ];
          modules = [
            {
              registry.settings.nodes = lib.mkForce (
                throw "Central reads and schema keys must not collect nodes."
              );
            }
          ];
        };
        shapeOnly = mkConsumer {
          schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
          centralModules = [ (throw "Listing schema keys must not evaluate central modules.") ];
          nodeModules.unused = [ (throw "Listing schema keys must not evaluate nodes.") ];
        };
      in
      {
        centralDomain = consumer.lib.registry.central.domain;
        localHost = consumer.nixosConfigurations.reader.config.registry.services.api.host;
        centralKeys = builtins.attrNames shapeOnly.lib.registry.central;
        combinedKeys = builtins.attrNames shapeOnly.lib.registry.combined;
        validates = (builtins.tryEval consumer.lib.registry.validate).success;
      };
    expected = {
      centralDomain = "example.test";
      localHost = "api.example.test";
      centralKeys = [
        "domain"
        "services"
      ];
      combinedKeys = [
        "domain"
        "services"
      ];
      validates = false;
    };
  };

  testStaticCombinedReadsLeaveAnInvalidServiceUnused = {
    expr =
      let
        consumer = mkConsumer {
          schemaModules = [ ../../examples/plain-nix/service-schema.nix ];
          centralModules = [ { domain = "example.test"; } ];
          nodeModules.publisher = [
            ({ config, ... }: {
              registry.services.api = {
                host = "api.${config.registry.combined.domain}";
                port = "invalid port";
              };
              environment.etc."registry-domain".text = config.registry.combined.domain;
            })
          ];
        };
        node = consumer.nixosConfigurations.publisher.config;
      in
      {
        domain = consumer.lib.registry.combined.domain;
        localHost = node.registry.services.api.host;
        sharedHost = consumer.lib.registry.combined.services.api.host;
        clientDomain = node.environment.etc."registry-domain".text;
        validates = (builtins.tryEval consumer.lib.registry.validate).success;
        nodeValidates = (builtins.tryEval node.registry.validate).success;
      };
    expected = {
      domain = "example.test";
      localHost = "api.example.test";
      sharedHost = "api.example.test";
      clientDomain = "example.test";
      validates = false;
      nodeValidates = false;
    };
  };
}
