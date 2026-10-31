# Diagnostics of static nodes and flake-parts projects name the option path,
# node, and available source files. Each regex lists those facts in message
# order.
{
  fixtures,
  helpers,
  lib,
  pkgs,
  registryLib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (registryLib) mkRegistry;
  inherit (helpers.diagnostics) fails rootCases validateNodeModules;
  serviceSchema = fixtures.schemas.service;

  mkProjectRegistry =
    modules:
    (helpers.mkProject { } (
      [
        (
          { config, ... }:
          {
            systems = [ ];
            flake.lib.registry = config.registry;
          }
        )
      ]
      ++ modules
    )).lib.registry;

  mkRegistryWithDuplicateSettings =
    settings:
    mkProjectRegistry [
      {
        _file = "/modules/first-project.nix";
        registry = settings;
      }
      {
        _file = "/modules/second-project.nix";
        registry = settings;
      }
    ];

  mkStaticNode =
    registry: modules:
    helpers.mkStaticNode {
      modules = [ registry.module ] ++ modules;
    };

  staticInvalidPort =
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ serviceSchema ];
        centralModules = [ { domain = "example.test"; } ];
        nodes."static service publisher" = mkStaticNode registry [ fixtures.invalidService ];
      };
    in
    {
      shared = registry.valid;
      local = (mkStaticNode registry [ fixtures.invalidService ]).config.registry.services.api.port;
    };
in
{
  static = rootCases (validateNodeModules mkStaticNode) // {
    testSharedInvalidPort = fails staticInvalidPort.shared "`services\\.api\\.port' is not of type[\\s\\S]*`node static service publisher: [^']*/invalid-service\\.nix'";

    testLocalInvalidPort = fails staticInvalidPort.local "`registry\\.services\\.api\\.port' is not of type[\\s\\S]*`[^']*/invalid-service\\.nix'";

    testFlakeCheckInvalidPort =
      fails
        (helpers.mkStaticConsumer {
          schemaModules = [ serviceSchema ];
          centralModules = [ { domain = "example.test"; } ];
          nodeModules."static service publisher" = [ fixtures.invalidService ];
        }).checks.${system}.registry.drvPath
        "`services\\.api\\.port' is not of type[\\s\\S]*`node static service publisher: [^']*/invalid-service\\.nix'";
  };

  flake = {
    testMissingSchema =
      fails
        (mkProjectRegistry [
          {
            registry.nodes = { };
          }
        ]).valid
        "registry\\.schemaModules must be set explicitly";

    testMissingNodes =
      fails
        (mkProjectRegistry [
          {
            registry.schemaModules = [ ];
          }
        ]).valid
        "registry\\.nodes must be set explicitly";

    testDuplicateNode =
      fails
        (mkRegistryWithDuplicateSettings {
          schemaModules = [ ];
          nodes."duplicate node" = { };
        }).valid
        "`registry\\.nodes\\.\"duplicate node\"' is defined multiple times[\\s\\S]*second-project\\.nix[\\s\\S]*first-project\\.nix";

    testCentralConflict =
      fails
        (mkProjectRegistry [
          {
            _file = "/modules/first-project.nix";
            registry = {
              schemaModules = [ serviceSchema ];
              nodes = { };
              centralModules = [ { domain = "first.example.test"; } ];
            };
          }
          {
            _file = "/modules/second-project.nix";
            registry.centralModules = [ { domain = "second.example.test"; } ];
          }
        ]).valid
        "`domain' has conflicting definition values[\\s\\S]*first-project\\.nix[\\s\\S]*second-project\\.nix";
  };
}
