/*
  Typed shared data across Nix configurations. The `dev` partition supplies
  development tools, checks, and focused evaluation.
*/
{
  description = "Typed shared data across Nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.flake-parts.flakeModules.partitions ];

      partitions.dev.module = ./dev;

      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
        legacyPackages = "dev";
      };

      flake = {
        lib = import ./lib;
        nixosModules.default = ./nixos/module.nix;
        flakeModules.default = ./flake-module.nix;
      };
    };
}
