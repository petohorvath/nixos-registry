{
  nixpkgs,
  mkRegistry,
  system,
}:
let
  example = import ../../examples/nixos { inherit mkRegistry nixpkgs system; };
in
{
  testNixosExampleEvaluatesAndValidates = {
    expr = example.result;
    expected = {
      central = {
        domain = "example.test";
        services = { };
      };
      combined = {
        domain = "example.test";
        services.metrics = {
          host = "monitor.example.test";
          port = 9191;
          endpoint = "monitor.example.test:9191";
        };
      };
      clientEndpoints = {
        "metrics publisher" = "monitor.example.test:9191";
        "standby publisher" = "monitor.example.test:9191";
      };
      validate = true;
    };
  };

  testNixosPublishesConfiguredServicePort = {
    expr = {
      service = example.registry.combined.services.metrics;
      configuredPort = example.nodes."metrics publisher".config.services.prometheus.port;
    };
    expected = {
      service = {
        host = "monitor.example.test";
        port = 9191;
        endpoint = "monitor.example.test:9191";
      };
      configuredPort = 9191;
    };
  };

  testDisabledNixosServiceDoesNotPublish = {
    expr = {
      services = builtins.attrNames example.registry.combined.services;
      inherit (example.nodes."standby publisher".config.services.prometheus) enable port;
    };
    expected = {
      services = [ "metrics" ];
      enable = false;
      port = 9292;
    };
  };

  testNixosNodesReadCombinedDataWhilePublishing = {
    expr = nixpkgs.lib.mapAttrs (_: node: {
      domain = node.config.networking.domain;
      endpoint = node.config.environment.etc."metrics-endpoint".text;
    }) example.nodes;
    expected = {
      "metrics publisher" = {
        domain = "example.test";
        endpoint = "monitor.example.test:9191";
      };
      "standby publisher" = {
        domain = "example.test";
        endpoint = "monitor.example.test:9191";
      };
    };
  };

  testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem = {
    expr =
      let
        pkgs = nixpkgs.legacyPackages.${system};
        alternatePkgs = pkgs.extend (
          _final: prev: {
            prometheus = prev.prometheus.overrideAttrs { pname = "registry-test-prometheus"; };
          }
        );
        package = alternatePkgs.prometheus;
        alternate = import ../../examples/nixos {
          inherit
            mkRegistry
            nixpkgs
            package
            system
            ;
        };
        config = alternate.nodes."metrics publisher".config;
        command = config.systemd.services.prometheus.serviceConfig.ExecStart;
      in
      {
        differentPackages = pkgs.prometheus.outPath != package.outPath;
        moduleSource = toString config.nixpkgs.flake.source;
        runsSelectedPackage = nixpkgs.lib.hasPrefix "${package}/bin/prometheus " command;
        port = alternate.registry.combined.services.metrics.port;
        inherit (alternate.registry) validate;
      };
    expected = {
      differentPackages = true;
      moduleSource = toString nixpkgs.outPath;
      runsSelectedPackage = true;
      port = 9191;
      validate = true;
    };
  };
}
