/*
  Completes backup destinations from partial central and node data.
  Local reads select supplied fields; the combined view holds complete records.
*/
{ lib, mkRegistry }:
let
  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [ ./partial-schema.nix ];
    centralModules = [
      { backupDestinations.archive.host = "archive.example.test"; }
    ];
  };

  nodes = {
    "address book" = mkNode {
      backupDestinations.offsite.host = "offsite.example.test";
    };
    "transport settings" = mkNode {
      backupDestinations.archive.port = 2222;
      backupDestinations.offsite.port = 8022;
    };
  };

  mkNode =
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
  localPort = nodes."transport settings".config.registry.backupDestinations.archive.port;
}
