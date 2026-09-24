{ lib, mkRegistry }:
let
  selectedLib = lib.extend (
    _final: _previous: {
      backupPortType = lib.types.port;
    }
  );
  registry = mkRegistry {
    lib = selectedLib;
    schemaModules = [
      (
        { lib, defaultPort, ... }:
        {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = ''
                Backup destination host.
              '';
            };
            port = lib.mkOption {
              type = lib.backupPortType;
              default = defaultPort;
              description = ''
                Backup destination port.
              '';
            };
          };
        }
      )
    ];
    centralModules = [ ({ centralHost, ... }: { host = centralHost; }) ];
    specialArgs = {
      defaultPort = 22;
      centralHost = "archive.example.test";
      nodePort = 1111;
    };
    nodes."backup job" = selectedLib.evalModules {
      specialArgs.nodePort = 2222;
      modules = [
        registry.module
        ({ nodePort, ... }: { registry.port = nodePort; })
      ];
    };
  };
in
{
  testUsesCallerLibraryAndKeepsNodeArgumentsSeparate = {
    expr = { inherit (registry) central combined; };
    expected = {
      central = {
        host = "archive.example.test";
        port = 22;
      };
      combined = {
        host = "archive.example.test";
        port = 2222;
      };
    };
  };
}
