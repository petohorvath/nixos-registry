{ lib, mkRegistry }:
{
  testLocallyEnabledOrderedPublicationExample = {
    expr = import ../examples/plain-nix/conditional-ordering.nix { inherit lib mkRegistry; };
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
    expr = import ../examples/plain-nix/priorities.nix { inherit lib mkRegistry; };
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
    expr = import ../examples/plain-nix { inherit lib mkRegistry; };
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
    expr =
      (builtins.tryEval (import ../examples/plain-nix/scalar-conflict.nix { inherit lib mkRegistry; }))
      .success;
    expected = false;
  };

  testPlainNixPartialContributionsExample = {
    expr = import ../examples/plain-nix/partial-contributions.nix { inherit lib mkRegistry; };
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
