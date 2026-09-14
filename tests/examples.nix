{ lib, mkRegistry }:
{
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
