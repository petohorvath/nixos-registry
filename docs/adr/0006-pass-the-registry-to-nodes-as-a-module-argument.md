---
status: proposed
---

# Pass the registry to nodes as a module argument

Every node imports the static NixOS module, which declares the node's contribution root under `registry` and takes the registry as the `registry` module argument. The generated module is the static module with the argument set. The registry is one attribute set, `mkRegistry`'s arguments other than `lib` plus `module`, `central`, `combined`, and `valid`, and the static flake module's `registry` option has the same shape.

Previously a node used one of two modules. The generated module typed `registry` with the schema, and the node read shared data from a `registry` argument that the caller passed through `specialArgs`. The static module put the schema settings and the shared data beside the contribution, under `registry.settings`, `registry.central`, `registry.combined`, and `registry.validate`. So the two modules read shared data at different paths, a schema field named `settings`, `central`, `combined`, or `validate` worked with only one of them, a node passed its schema twice, and an override of the whole contribution also overrode the static module's settings and shared data.

## Decisions

- **One static module for every node.** The static NixOS module declares only the contribution root. Its type comes from the schema in the `registry` argument, so local reads stay typed and option listings show the schema's options.
- **The registry as a module argument.** `registry.module` sets `_module.args.registry`. A node that reads the registry while it selects its imports also passes it through `specialArgs`, which the module system resolves first; both must be the same registry, because nothing in pure Nix tells two registries apart cheaply.
- **A flat registry.** The registry holds its inputs and its results under one name, so `mkRegistry`'s result, the project-level `config.registry`, and the node's argument have the same shape. `validate` becomes `valid`, a value rather than a verb, and `specialArgs` becomes `moduleArgs`, which names the modules it reaches rather than reusing the node's `specialArgs`.

## Consequences

- No schema name is reserved apart from `_module`, and an override of the whole contribution changes only the contribution.
- `lib/static-interface.nix`, which stripped the settings and shared data out of contributions, is removed.
- A node reads shared data as `registry.combined`, beside its own contribution at `config.registry`; in a module that writes `registry.<path>` and reads `registry.combined`, the same prefix names both.
- The shared data is a module argument, not an option, so it is not type-checked and does not appear in option listings.
- `registry.module` can be imported once per node; two imports define the argument twice. A module key would deduplicate them, but no registry has a unique string to key on.
- Building a node's option tree evaluates the schema's declarations, as the generated module already did. Central modules and nodes stay unevaluated until shared data is read.
- `registry.nodes` is reachable from every node. Shared data still belongs in contributions.

## Considered options

- **Settings and shared data in a second option** beside `registry`, such as `sharedRegistry`. It keeps shared data typed and listed, but gives every node two top-level names, and the project-level `config.registry` and the node's option would differ.
- **The contribution nested under the registry option**, such as `registry.contribution.<path>`. It keeps one name, but lengthens every contribution path and leaves an override of the whole `registry` option able to discard the settings.
- **Keeping both modules.** It keeps the existing paths, with their reserved names, duplicated schema, and two read paths.
