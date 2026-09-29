{
  formatter,
  inputs,
  pkgs,
  self,
  system,
}:
import ../tests {
  inherit formatter pkgs system;
  inherit (inputs) nixpkgs;
  flake = self;
  flakeParts = inputs.flake-parts;
}
