# Typed shared data with independently evaluated development tools.
{
  description = "Typed shared data across Nix configurations";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      development = import ./dev {
        inherit (inputs) nixpkgs;
        inherit systems;
      };
    in
    {
      nixosModules.default = import ./modules/nixos.nix;
      flakeModules.default = import ./modules/flake.nix;
      lib = import ./lib // development.lib;

      inherit (development) checks devShells formatter;
    };
}
