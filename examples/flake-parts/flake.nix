# Flake-parts adoption with caller-owned schemas and separate source inputs.
{
  description = "Typed shared data in a flake-parts configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # Import public exports from source, avoiding the root development input graph.
    nixos-registry = {
      url = "path:../..";
      flake = false;
    };
    servicePublisher.url = "path:../sources/service-publisher";
    backupClient.url = "path:../sources/backup-client";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } ./module.nix;
}
