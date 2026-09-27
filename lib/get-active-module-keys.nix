# List the keys of modules that remain active in an evaluated module graph.
# Disabled modules hide the modules they import.
{ lib }:
graph:
lib.pipe graph [
  (lib.filter (module: !module.disabled))
  (
    modules:
    builtins.genericClosure {
      startSet = modules;
      operator = module: lib.filter (imported: !imported.disabled) module.imports;
    }
  )
  (map (module: module.key))
]
