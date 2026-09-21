# Whole-contribution overrides select records before nested options merge.
{ lib, mkRegistry }:
let
  mkExample =
    publication:
    let
      registry = mkRegistry {
        inherit lib;
        schemaModules = [ ./schema.nix ];
        centralModules = [
          {
            _file = toString ./priorities.nix;
            backupDestinations = {
              archive = {
                host = "archive.example.test";
                port = 22;
                paths = [ "/central" ];
              };
              offsite = {
                host = "offsite.example.test";
                port = 22;
              };
            };
          }
        ];
        nodes."backup policy" = lib.evalModules {
          modules = [
            registry.module
            {
              _file = toString ./priorities.nix;
              registry = publication;
            }
          ];
        };
      };
    in
    {
      inherit (registry) combined validate;
    };

  replacement.backupDestinations.archive = {
    host = "replacement.example.test";
    port = 2222;
  };
in
{
  defaultContribution = mkExample (lib.mkDefault replacement);
  forcedContribution = mkExample (lib.mkForce replacement);
  forcedPort = mkExample {
    backupDestinations.archive.port = lib.mkForce 2222;
  };
}
