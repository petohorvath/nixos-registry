# Public exports loaded by path from the source tree, without the root flake.
{
  lib = import ../../lib;
  nixosModules.default = ../../nixos/module.nix;
  flakeModules.default = ../../flake-module.nix;
}
