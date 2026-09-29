# Whole-contribution ordering fails as direct evaluation does, through both
# node adapters: 2 adapters x 2 sources x 3 orders x 3 or 4 outputs.
{
  exports,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;
  adapters = {
    generated = { };
    static.mkNode =
      {
        registry,
        schemaModules,
        definitions,
      }:
      nixpkgs.lib.nixosSystem {
        modules = [
          exports.nixosModules.default
          {
            nixpkgs.hostPlatform = system;
            registry = {
              settings = { inherit schemaModules; };
              inherit (registry) central combined validate;
            };
          }
        ]
        ++ map (registry: { inherit registry; }) definitions;
      };
  };
  orders = {
    before = lib.mkBefore;
    after = lib.mkAfter;
    explicit = lib.mkOrder 750;
  };
  mkSourceCases =
    adapter: source:
    lib.mapAttrs (
      _: mkOrdered:
      let
        ordered = mkOrdered { backupPaths = [ "/ordered" ]; };
        evaluations =
          import ./fixtures/evaluate-properties.nix
            (
              {
                inherit lib;
                inherit (exports.lib) mkRegistry;
              }
              // adapter
            )
            (
              if source == "central" then
                {
                  central = [ ordered ];
                  contributions.publisher = [ { backupPaths = [ "/node" ]; } ];
                }
              else
                {
                  central = [ { backupPaths = [ "/central" ]; } ];
                  contributions.publisher = [ ordered ];
                }
            );
        outputs = {
          testDirect = "direct";
          testCombined = "combined";
          testValidate = "validate";
        }
        // lib.optionalAttrs (source == "central") { testCentral = "central"; };
      in
      lib.mapAttrs (_: output: {
        expr = evaluations.${output};
        expectedError = {
          type = "TypeError";
          msg = "unexpected argument 'priority'";
        };
      }) outputs
    ) orders;
in
lib.mapAttrs (
  _: adapter:
  lib.genAttrs [
    "central"
    "node"
  ] (mkSourceCases adapter)
) adapters
