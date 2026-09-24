{
  lib = import ../../lib;
  nixosModules.default = ../../nixos/module.nix;
  flakeModules.default = ../../flake-module.nix;
}
