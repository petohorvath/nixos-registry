/*
  The static NixOS module: declare a node's contribution root, typed by the
  schema of the registry in the `registry` module argument. The registry's
  generated module imports the same implementation and sets that argument; a
  node can also receive the registry through its `specialArgs`.
*/
{
  imports = [ ../lib/static-module.nix ];
}
