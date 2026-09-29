{ inputs, self, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      formatter = pkgs.callPackage ./formatter.nix { };
      devShells.default = pkgs.callPackage ./shell.nix {
        inherit (config) formatter;
      };
      checks = import ./checks.nix {
        inherit
          inputs
          pkgs
          self
          system
          ;
        inherit (config) formatter;
      };
    };
}
