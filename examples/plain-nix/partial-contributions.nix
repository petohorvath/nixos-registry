/*
  Completes backup destinations from partial central and participant data.
  Local reads select supplied fields; the combined view holds complete records.
*/
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib participants;
    schemaModules = [ ./partial-schema.nix ];
    centralModules = [
      { backupDestinations.archive.host = "archive.example.test"; }
    ];
  };

  participants = {
    "address book" = mkParticipant {
      backupDestinations.offsite.host = "offsite.example.test";
    };
    "transport settings" = mkParticipant {
      backupDestinations.archive.port = 2222;
      backupDestinations.offsite.port = 8022;
    };
  };

  mkParticipant =
    publication:
    lib.evalModules {
      modules = [
        registry.module
        { registry = publication; }
      ];
    };
in
{
  inherit (registry) combined validate;
  centralHost = registry.central.backupDestinations.archive.host;
  localPort = participants."transport settings".config.registry.backupDestinations.archive.port;
}
