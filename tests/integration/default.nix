{
  flake-parts,
  nixpkgs,
  self,
  system,
}:
let
  testContext = import ../test-context.nix {
    inherit
      flake-parts
      nixpkgs
      self
      system
      ;
  };
in
{
  diagnostics = import ./diagnostics.nix testContext;
  flake-module = import ./flake-module.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
  flake-parts-example = import ./flake-parts-example.nix testContext;
  nixos-example = import ./nixos-example.nix testContext;
  nixos-module = import ./nixos-module.nix testContext;
  recursion = import ./recursion.nix testContext;
  static-reads = import ./static-reads.nix testContext;
}
