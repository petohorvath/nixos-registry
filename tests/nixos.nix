{
  nixpkgs,
  alternateNixpkgs,
  mkRegistry,
}:
let
  example = import ../examples/nixos { inherit mkRegistry nixpkgs; };
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
      configuredPort = example.participants."metrics publisher".config.services.prometheus.port;
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
      inherit (example.participants."standby publisher".config.services.prometheus) enable port;
    };
    expected = {
      services = [ "metrics" ];
      enable = false;
      port = 9292;
    };
  };

  testNixosParticipantsReadCombinedDataWhilePublishing = {
    expr = nixpkgs.lib.mapAttrs (_: participant: {
      domain = participant.config.networking.domain;
      endpoint = participant.config.environment.etc."metrics-endpoint".text;
    }) example.participants;
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
        package = alternateNixpkgs.legacyPackages.x86_64-linux.prometheus;
        alternate = import ../examples/nixos {
          inherit mkRegistry nixpkgs package;
        };
        config = alternate.participants."metrics publisher".config;
        command = config.systemd.services.prometheus.serviceConfig.ExecStart;
      in
      {
        differentSources = nixpkgs.outPath != alternateNixpkgs.outPath;
        moduleSource = toString config.nixpkgs.flake.source;
        runsSelectedPackage = nixpkgs.lib.hasPrefix "${package}/bin/prometheus " command;
        port = alternate.registry.combined.services.metrics.port;
        inherit (alternate.registry) validate;
      };
    expected = {
      differentSources = true;
      moduleSource = toString nixpkgs.outPath;
      runsSelectedPackage = true;
      port = 9191;
      validate = true;
    };
  };
}
