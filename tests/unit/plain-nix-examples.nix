{ fixtures, ... }:
{
  testNodeContributesFromCombinedDomainExample = {
    expr = fixtures.examples.combined-reads;
    expected = {
      centralDomain = "example.test";
      localHost = "api.example.test";
      clientEndpoint = "api.example.test:8443";
      combined = {
        domain = "example.test";
        services.api = {
          host = "api.example.test";
          port = 8443;
          endpoint = "api.example.test:8443";
        };
      };
      validate = true;
    };
  };

  testLazyCollectionExampleReadsSiblingEntries = {
    expr = fixtures.examples.collection-laziness.lazy;
    expected = {
      combined.settings = {
        domain = "example.test";
        endpoint = "api.example.test:8443";
      };
      validate = true;
    };
  };

  testLocallyEnabledOrderedContributionExample = {
    expr = fixtures.examples.conditional-ordering;
    expected = {
      enabled = {
        combined.backupDestinations.archive = {
          host = "archive.example.test";
          port = 22;
          paths = [
            "/srv/documents"
            "/srv/central"
            "/srv/snapshots"
          ];
        };
        backupCommand = "backup archive.example.test /srv/documents /srv/central /srv/snapshots";
        validate = true;
      };
      disabled = {
        combined.backupDestinations.archive = {
          host = "archive.example.test";
          port = 22;
          paths = [ "/srv/central" ];
        };
        backupCommand = "backup archive.example.test /srv/central";
        validate = true;
      };
    };
  };

  testPlainNixContributionPrioritiesExample = {
    expr = fixtures.examples.priorities;
    expected = {
      defaultContribution = {
        combined.backupDestinations = {
          archive = {
            host = "archive.example.test";
            port = 22;
            paths = [ "/central" ];
          };
          offsite = {
            host = "offsite.example.test";
            port = 22;
            paths = [ ];
          };
        };
        validate = true;
      };
      forcedContribution = {
        combined.backupDestinations.archive = {
          host = "replacement.example.test";
          port = 2222;
          paths = [ ];
        };
        validate = true;
      };
      forcedPort = {
        combined.backupDestinations = {
          archive = {
            host = "archive.example.test";
            port = 2222;
            paths = [ "/central" ];
          };
          offsite = {
            host = "offsite.example.test";
            port = 22;
            paths = [ ];
          };
        };
        validate = true;
      };
    };
  };

  testPlainNixBackupDestinationExample = {
    expr = fixtures.examples.plain-nix;
    expected = {
      central.backupDestinations.archive = {
        host = "archive.example.test";
        port = 22;
        paths = [ "/srv/central" ];
      };
      combined.backupDestinations = {
        archive = {
          host = "archive.example.test";
          port = 22;
          paths = [
            "/srv/central"
            "/srv/documents"
          ];
        };
        local = {
          host = "local.example.test";
          port = 8022;
          paths = [ "/srv/photos" ];
        };
        offsite = {
          host = "offsite.example.test";
          port = 2222;
          paths = [ ];
        };
      };
      backupCommand = "backup archive.example.test local.example.test";
      validate = true;
    };
  };

  testPlainNixScalarConflictExampleFails = {
    expr = fixtures.examples.scalar-conflict;
    expectedError.msg = "`backupDestinations\\.archive\\.host' has conflicting definition values[\\s\\S]*`node conflicting backup job: ";
  };

  testPlainNixPartialContributionsExample = {
    expr = fixtures.examples.partial-contributions;
    expected = {
      centralHost = "archive.example.test";
      localPort = 2222;
      combined.backupDestinations = {
        archive = {
          host = "archive.example.test";
          port = 2222;
          paths = [ "/srv/default" ];
          endpoint = "archive.example.test:2222";
          command = "backup archive.example.test:2222";
        };
        offsite = {
          host = "offsite.example.test";
          port = 8022;
          paths = [ "/srv/default" ];
          endpoint = "offsite.example.test:8022";
          command = "backup offsite.example.test:8022";
        };
      };
      validate = true;
    };
  };
}
