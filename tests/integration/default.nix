let
  rootInputs = (builtins.getFlake (toString ../..)).inputs;
  rebuild = import ../helpers/evaluation-inputs.nix;
in
{
  nixpkgs ? rootInputs.nixpkgs,
  # flake-parts follows nixpkgs, so rebuild it against the selected one.
  flake-parts ? rebuild {
    path = rootInputs.flake-parts.outPath;
    inputs.nixpkgs-lib = nixpkgs;
  },
  system ? builtins.currentSystem,
}:
let
  testContext = import ../test-context.nix { inherit flake-parts nixpkgs system; };
in
{
  diagnostics = import ./diagnostics.nix testContext;
  flake-module = import ./flake-module.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
  flake-parts = import ./flake-parts.nix testContext;
  nixos-example = import ./nixos-example.nix testContext;
  nixos-module = import ./nixos-module.nix testContext;
  recursion = import ./recursion.nix testContext;
  static-interface = import ./static-interface.nix testContext;
  static-nixos = import ./static-nixos.nix testContext;
  static-reads = import ./static-reads.nix testContext;
}
