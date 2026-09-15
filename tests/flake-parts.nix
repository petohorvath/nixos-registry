{ example }:
{
  testFlakePartsExampleEvaluatesAndValidates = {
    expr = example.lib.result;
    expected = {
      central = {
        domain = "example.test";
        services = { };
      };
      combined = {
        domain = "example.test";
        services = {
          api = {
            host = "api.example.test";
            port = 8443;
            endpoint = "api.example.test:8443";
          };
          backup = {
            host = "backup.example.test";
            port = 8022;
            endpoint = "backup.example.test:8022";
          };
        };
      };
      backupCommand = "backup --api api.example.test:8443";
      validate = true;
    };
  };

  testSeparateSourceParticipantsKeepLocalContributionsDistinct = {
    expr = builtins.mapAttrs (_: participant: {
      port = participant.config.port;
      serviceNames = builtins.attrNames participant.config.registry.services;
    }) example.lib.participants;
    expected = {
      "api publisher" = {
        port = 8443;
        serviceNames = [ "api" ];
      };
      "backup consumer" = {
        port = 8022;
        serviceNames = [ "backup" ];
      };
    };
  };
}
