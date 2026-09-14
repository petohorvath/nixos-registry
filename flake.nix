# Typed shared data for caller-built Nix module evaluations.
{
  description = "Typed shared data across Nix configurations";

  outputs = _inputs: {
    lib.mkRegistry = import ./lib/mk-registry.nix;
  };
}
