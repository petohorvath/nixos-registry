# API reference

The flake exports `lib.mkRegistry`, a function that returns a registry built from central modules and named nodes; `nixosModules.default`, the static NixOS module that declares a node's contribution root; and `flakeModules.default`, a flake-parts module that holds a registry at the project's `registry` option. The consuming project supplies the option declarations and evaluates the node configurations.

Start with the complete [README example](../README.md#usage). The [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules) explains the underlying `lib.evalModules` function.

## Call `mkRegistry`

The following call assumes that `schema.nix`, `central.nix`, and `nixosConfigurations` are defined by the consuming project:

```nix
registry = inputs.nixos-registry.lib.mkRegistry {
  lib = inputs.nixpkgs.lib;
  schemaModules = [ ./schema.nix ];
  nodes = nixosConfigurations;
  centralModules = [ ./central.nix ];
  moduleArgs = { };
};
```

The function takes one attribute set with these arguments:

| Argument         | Value                                                                                                                          | Default                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------ |
| `lib`            | Nixpkgs library that supplies the module system and option types                                                               | Required                 |
| `schemaModules`  | List of modules that declare the shared options                                                                                | Required                 |
| `nodes`          | Attribute set of named, evaluated configurations                                                                               | Required; `{ }` is valid |
| `centralModules` | List of modules that define values for the shared options                                                                      | `[ ]`                    |
| `moduleArgs`     | Attribute set of arguments for schema and central module evaluation, including the schema within each node's `registry` option | `{ }`                    |

### `lib`

Use the same Nixpkgs module-system revision for this argument and every node. For NixOS, use the same `nixpkgs` input for `lib` and `nixpkgs.lib.nixosSystem`.

The root `nixpkgs` input selects the repository's tools and test baselines. The caller-supplied `lib` remains authoritative for registry evaluation. Extra libraries or module arguments required by the schema must be supplied by the consuming project.

Package selection is separate from module-system selection. A NixOS configuration can use a package from another Nixpkgs input while retaining its selected module system. The [NixOS example](examples.md#nixos) demonstrates this.

### Plain-import access

The public exports load by path from the source tree without supplying or evaluating any flake inputs:

| Path               | Export                                      |
| ------------------ | ------------------------------------------- |
| `lib`              | Attribute set containing only `mkRegistry`  |
| `nixos/module.nix` | [Static NixOS module](#nodes)               |
| `flake-module.nix` | [Static flake module](#static-flake-module) |

A consumer can obtain the repository as a source-only flake input with `flake = false` and import these paths:

```nix
inherit (import "${inputs.nixos-registry}/lib") mkRegistry;
registry = mkRegistry {
  inherit lib nodes schemaModules;
};
```

Use the same caller-provided `lib` for node evaluation. Import the static modules as `"${inputs.nixos-registry}/nixos/module.nix"` and `"${inputs.nixos-registry}/flake-module.nix"`. The root flake's `lib` output imports the same `lib` directory, and its `nixosModules.default` and `flakeModules.default` outputs reference the same module files.

Plain import through the flake's `outputs` function no longer works because the root flake is assembled with flake-parts. Normal flake consumption adds the root `nixpkgs`, `flake-parts`, `nix-unit`, and `treefmt-nix` inputs to a consumer's lock graph. The `nix-unit` input serves only the project's tests and follows `nixpkgs`; a consumer can leave it out with `inputs.nixos-registry.inputs.nix-unit.follows = "";`. The `treefmt-nix` input serves only the project's development checks and follows `nixpkgs`; a consumer can leave it out with `inputs.nixos-registry.inputs.treefmt-nix.follows = "";`. This supersedes the original v1 specification's input-free-flake promise; constructor arguments, defaults, and registry behavior are preserved. See the [migration notes](../CHANGELOG.md#breaking-flake-parts-root) and [ADR 0002](adr/0002-assemble-the-root-flake-with-flake-parts.md).

### `schemaModules`

Declare shared options at their own paths, such as `options.services`. The generated module places those options under `registry` in each node. The [service schema](../examples/plain-nix/service-schema.nix) is a complete example with required fields and a derived endpoint.

Schema modules can declare types, defaults, and derived values. Keep the declarations, their structure, and their arguments independent of node evaluation. Shared option declarations belong here; node contributions cannot add them.

### `nodes`

Each value must be an evaluated configuration that imports the registry's `module`. Both `nixpkgs.lib.nixosSystem` and `lib.evalModules` produce suitable results. Pass the whole evaluation result, including its `options`, rather than only its `config` attribute.

The attribute name identifies the node in diagnostics. It need not match a hostname, service name, or source repository. For example:

```nix
nodes = {
  "metrics publisher" = nixpkgs.lib.nixosSystem {
    modules = [ registry.module ./server.nix ];
  };
};
```

An independently declared option named `registry` does not replace the static NixOS module. A node with a missing or incompatible option produces an error naming the node and the required import.

### `centralModules`

Define shared values directly against the schema, without the `registry` prefix. For example, a central module can set `services.metrics.port = 9090;` when the schema declares `services` with that field.

Central definitions have the same precedence as ordinary node definitions. Use `lib.mkDefault`, `lib.mkForce`, or `lib.mkOverride` when a different precedence is needed.

### `moduleArgs`

The `moduleArgs` argument supplies arguments to the schema and central module evaluations, including the schema within each node's `registry` option. It does not supply arguments to the node's own modules; pass those through `nixosSystem.specialArgs` or `lib.evalModules`'s `specialArgs`.

## The registry

`mkRegistry` returns the registry, an attribute set of its arguments other than `lib` and its results:

| Attribute        | Value                                 | Use                                                                        |
| ---------------- | ------------------------------------- | -------------------------------------------------------------------------- |
| `schemaModules`  | List of modules                       | The `schemaModules` argument.                                              |
| `nodes`          | Attribute set of evaluated nodes      | The `nodes` argument.                                                      |
| `centralModules` | List of modules                       | The `centralModules` argument, or its default.                             |
| `moduleArgs`     | Attribute set                         | The `moduleArgs` argument, or its default.                                 |
| `module`         | Nix module                            | The generated module; import it in each node, as [Nodes](#nodes) shows.    |
| `central`        | Attribute set of shared option values | Read data from the schema and central modules, without node contributions. |
| `combined`       | Attribute set of shared option values | Read data from the schema, central modules, and all node contributions.    |
| `valid`          | Boolean value, or an evaluation error | Demand all combined data. Valid data produces `true`.                      |

Both data sets include schema defaults and derived values. Either can remain incomplete if its definitions lack required fields.

Every node receives the whole registry, including `nodes`. Shared data belongs in contributions: reading another node's configuration through `registry.nodes` bypasses the schema, its merge rules, and validation.

## Nodes

`registry.module`, the generated module, imports the static NixOS module and passes the registry to the node as its `registry` module argument:

```nix
nixpkgs.lib.nixosSystem {
  modules = [
    registry.module
    ({ config, registry, ... }: {
      registry.services.metrics.port = config.services.prometheus.port;
      environment.etc."metrics-endpoint".text =
        registry.combined.services.metrics.endpoint;
    })
  ];
}
```

The schema determines the available shared options. The `registry` prefix is added only in node configurations:

| Place                      | Example path                              | Meaning                                  |
| -------------------------- | ----------------------------------------- | ---------------------------------------- |
| Schema module              | `options.services`                        | Declare the shared option.               |
| Central module             | `services.metrics.port`                   | Define a shared value outside the nodes. |
| Node configuration         | `registry.services.metrics.port`          | Contribute a value from this node.       |
| Node's local configuration | `config.registry.services.metrics.port`   | Read this node's own value.              |
| `registry` module argument | `registry.central.services.metrics.port`  | Read the central value.                  |
| `registry` module argument | `registry.combined.services.metrics.port` | Read the merged value.                   |
| `registry` module argument | `registry.valid`                          | Validate all combined data.              |

`config.registry` contains only the node's local contribution, typed by the schema; its options appear in option listings such as `options.registry`. The `registry` argument is the whole registry.

Import `registry.module` once per node; a second import, even of the same registry's module, fails because `_module.args.registry` is defined multiple times. A module from another source can import `nixosModules.default`, or `nixos/module.nix` by path, to contribute without access to the registry. The module system loads the static module once, and the node still needs `registry.module`, or the `registry` argument through `specialArgs`; without the argument, reading `config.registry` fails with an error that names `registry.module`.

A registry passed through `specialArgs` takes precedence over the one `registry.module` sets, as for any module argument, and the library cannot tell two registries apart. Pass the same registry through both.

No schema name is reserved apart from `_module`. A schema can declare `settings`, `central`, `combined`, or `valid`; they are ordinary fields under `config.registry` and in the shared data.

Nodes can add entries beneath declared collection options. For example, declaring a `services` option with `attrsOf (submodule ...)` allows a node to add `services.metrics` without a central declaration for that entry.

Contributions cannot add shared option declarations, including through submodule functions or imports. Data-only submodule functions retain their normal module arguments. `registry._module` is reserved for module-system controls, and a freeform registry root is unsupported. Declared options can use collection types or freeform data within their own types.

## Static flake module

Import `inputs.nixos-registry.flakeModules.default` into a flake-parts configuration. It evaluates one registry with the enclosing evaluator's `lib` and holds it at the project's `registry` option, with the same attributes that `mkRegistry` returns:

| Project option            | Meaning                                                                   | Default                  |
| ------------------------- | ------------------------------------------------------------------------- | ------------------------ |
| `registry.schemaModules`  | Shared option declarations; lists from project modules concatenate.       | Required; `[ ]` is valid |
| `registry.nodes`          | Named, whole node evaluation results, including `options`.                | Required; `{ }` is valid |
| `registry.centralModules` | Central definitions; lists from project modules concatenate.              | `[ ]`                    |
| `registry.moduleArgs`     | Arguments for schema and central evaluation, including the node's schema. | `{ }`                    |
| `registry.module`         | Read-only generated module, which passes this registry to the node.       | Computed                 |
| `registry.central`        | Read-only central data.                                                   | Computed                 |
| `registry.combined`       | Read-only combined data.                                                  | Computed                 |
| `registry.valid`          | Read-only explicit validation, returning `true` or raising an error.      | Computed                 |

Supply required settings explicitly, even when empty. Settings may be split across project modules. Distinct node names and argument keys compose; each value is kept opaque and lazy. Multiple definitions of the same node name or argument key at the same override priority fail when demanded, even if identical. Normal overrides such as `lib.mkDefault` and `lib.mkForce` select definitions before that check. Module lists retain definition origins, and conflicting central values use the schema's ordinary merge rules.

The caller constructs every node, chooses its module arguments, and selects registry membership through `registry.nodes`. Configurations elsewhere in `flake.nixosConfigurations` are not automatically enrolled. Names need not match hostnames. Registry `moduleArgs` does not replace the arguments passed separately to `nixosSystem`.

Import `config.registry.module` in each node:

```nix
# In a flake-parts module receiving { config, inputs, ... }:
mkNode = module: inputs.nixpkgs.lib.nixosSystem {
  modules = [ config.registry.module module ];
};
```

The [complete usage example](examples.md#static-flake-module) shows node construction and a validation check. Align `flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs"` with the input used by `nixosSystem`, so the enclosing evaluator and nodes use the same module-system revision. The producer's development input does not select registry semantics.

Reading a result demands only that value; importing the flake module does not install or force a validation check. The [separate-source example](examples.md#flake-parts-and-separate-source-repositories) explicitly demands `registry.valid` in its flake check. Flake-parts remains optional for `mkRegistry` consumers.

## Partial records, defaults, and derived values

Different contributions can supply different required fields of one record. The shared evaluation merges the definitions before it evaluates the completed record.

For example, a central module can supply a host and a node can supply its port:

```nix
# In a central module:
backupDestinations.archive.host = "archive.example.test";

# In a node:
registry.backupDestinations.archive.port = 2222;
```

With the [partial-record schema](../examples/plain-nix/partial-schema.nix), `registry.combined.backupDestinations.archive` contains:

```nix
{
  host = "archive.example.test";
  port = 2222;
  paths = [ "/srv/default" ];
  endpoint = "archive.example.test:2222";
  command = "backup archive.example.test:2222";
}
```

The node's local record still lacks a host. Its port can be read from `config.registry`, but reading its missing host or derived endpoint fails. The central record likewise lacks a port. Use `registry.combined` to read the completed record.

Schema defaults apply once per shared evaluation, regardless of node count. An explicit list definition, including `[ ]`, replaces its schema default. Multiple explicit lists merge normally. Derived values use the fields from that evaluation; read-only defaults in the combined data therefore use the combined fields. Additional definitions of read-only values fail under normal module rules.

## Override a field or a whole contribution

Ordinary lists merge. Equal scalar definitions agree; conflicting scalar definitions raise errors. Central definitions and node definitions follow the same rules.

Override priorities select which definitions remain:

| Definition                    | Override priority   |
| ----------------------------- | ------------------- |
| `lib.mkForce value`           | 50                  |
| Ordinary definition           | 100                 |
| `lib.mkDefault value`         | 1000                |
| `lib.mkOverride number value` | The supplied number |

The lowest number wins. Definitions with the same priority merge according to their option types.

Apply an override to a field to change only that field:

```nix
registry.backupDestinations.archive.port = lib.mkForce 2222;
```

Apply an override to the whole `registry` option to select a whole contribution:

```nix
registry = lib.mkForce {
  backupDestinations.archive = {
    host = "replacement.example.test";
    port = 2222;
  };
};
```

The second form discards every weaker contribution in full, including unrelated fields. Required fields in discarded contributions cannot complete the remaining record. Nested priorities apply only within the contributions that remain.

Central modules set a priority for the whole contribution with `config = lib.mkForce { ... };` or another override. A central module containing only imports adds no contribution of its own. Node overrides affect `registry.combined`; `registry.central` still evaluates only central modules. A whole-contribution override changes only the node's contribution, not its `registry` argument.

The [priority example](../examples/plain-nix/priorities.nix) compares a default contribution, a forced contribution, and an override of one port.

## Conditions and list ordering

Use `lib.mkIf` for conditional definitions and `lib.mkMerge` to combine definition fragments:

```nix
registry = lib.mkIf config.backup.enable (
  lib.mkMerge [
    { backupDestinations.archive.paths = lib.mkBefore config.backup.paths; }
    { backupDestinations.archive.paths = lib.mkAfter [ "/srv/snapshots" ]; }
  ]
);
```

In the [conditional-ordering example](../examples/plain-nix/conditional-ordering.nix), enabled contributions produce `[ "/srv/documents" "/srv/central" "/srv/snapshots" ]`. Disabling the contribution leaves only `[ "/srv/central" ]` from the central module.

List ordering applies across central and node definitions after override priorities select the definitions to keep:

| List definition             | Order priority      |
| --------------------------- | ------------------- |
| `lib.mkBefore values`       | 500                 |
| Ordinary definition         | 1000                |
| `lib.mkAfter values`        | 1500                |
| `lib.mkOrder number values` | The supplied number |

Lower numbers come first. Apply ordering to nested list options. Ordering the whole `registry` option fails with both tested Nixpkgs revisions, as it does in direct module evaluation.

Whole contributions and nested values follow normal module conditions. Discarded definitions retain the module system's evaluation behavior. `lib.mkMerge` can combine partial records without first completing each local record.

## Evaluation and recursion

Reading one shared field does not evaluate all other fields. An invalid service port can remain unused while an independent domain value is read. `registry.valid` explicitly evaluates the complete combined data.

A contribution can read shared data when the schema and value dependencies permit it. The [combined-read example](../examples/plain-nix/combined-reads.nix) uses:

```nix
registry.services.api.host = "api.${registry.combined.domain}";
clientEndpoint = registry.combined.services.api.endpoint;
```

The central data supplies the domain and port. The combined data completes the record and derives its endpoint without demanding a complete local record.

An unrelated invalid contribution can remain unused while reading an independent combined field. Central reads do not collect nodes. Building a node's option tree evaluates the schema's declarations, but reading unrelated node configuration leaves central modules unevaluated and nodes uncollected. The [static consumer tests](../tests/integration/static-reads.nix) exercise these reads and explicit validation through a flake-parts project.

Collection types can force related definitions during merging. In the [collection example](../examples/plain-nix/collection-laziness.nix), both values are under one `settings` option:

```nix
# In a central module:
settings.domain = "example.test";

# In a node:
registry.settings.endpoint = "api.${registry.combined.settings.domain}:8443";
```

| Type of `settings`                    | Result with both tested Nixpkgs revisions                                                                             |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `lib.types.attrsOf lib.types.str`     | Reading the domain or validating recurses. Merging inspects the endpoint definition, which reads the same collection. |
| `lib.types.lazyAttrsOf lib.types.str` | Both values evaluate, and validation returns `true`.                                                                  |

The complete schema determines what gets evaluated. For example, `attrsOf (submodule ...)` in the combined-read example keeps the fields within each service record lazy. `lazyAttrsOf` has its own [limitations with conditional definitions](https://nixos.org/manual/nixos/stable/#sec-option-types-composed).

Lazy collections do not resolve value cycles. If one service reads a second service and the second reads the first, shared reads and validation can raise Nix's `infinite recursion encountered` error. The [value-cycle example](../examples/plain-nix/value-cycle.nix) demonstrates this.

### Schema and central data during node setup

Both data sets get their top-level keys from the schema. Listing those keys does not evaluate central definitions or collect node contributions:

```nix
builtins.attrNames registry.central
builtins.attrNames registry.combined
```

The `registry` argument that `registry.module` sets comes from the node's configuration, so imports cannot depend on it; selecting imports from it causes a module-system cycle, even for an independent central value. To inspect schema keys or read available `registry.central` values while selecting imports, also pass the registry through the node's `specialArgs`, which the module system resolves before configuration:

```nix
nixpkgs.lib.nixosSystem {
  specialArgs = { inherit registry; };
  modules = [
    registry.module
    ({ registry, ... }: {
      imports = lib.optional (registry.central.monitoring.enable) ./monitoring.nix;
    })
  ];
}
```

Reading `registry.central` this way does not collect node contributions.

Keep schema declarations, their structure, and their arguments independent of node evaluation. Central values used to set up a node must also have independent dependencies. A central definition that reads node data can cause recursion.

## Validation and diagnostics

`registry.valid` evaluates all combined data. Valid data returns `true`; invalid data raises a Nix evaluation error. It does not separately require every local or central record to be complete.

To make validation part of a flake check, use this pattern with a package set for the selected `system`:

```nix
checks.${system}.registry =
  assert registry.valid;
  pkgs.runCommand "registry-validation" { } ''
    touch "$out"
  '';
```

With the static flake module, capture the project-level registry before entering `perSystem`:

```nix
{ config, ... }:
let
  shared = config.registry;
in
{
  perSystem = { pkgs, ... }: {
    checks.registry =
      assert shared.valid;
      pkgs.runCommand "registry-validation" { } ''
        touch "$out"
      '';
  };
}
```

Run `nix build --no-update-lock-file --no-link .#checks.<system>.registry` for this check alone, replacing `<system>` with a system from `systems`. Evaluating the check demands complete combined data and reports schema errors before a derivation can build. Defining the check leaves ordinary reads lazy; neither static module installs or demands a validation check automatically. The [static example](examples.md#static-flake-module) includes this wiring. Full `nix flake check --no-update-lock-file` also validates other consumer outputs, so exported NixOS configurations must include their machine-specific boot and filesystem settings.

| Combined data                                               | Result                                                             |
| ----------------------------------------------------------- | ------------------------------------------------------------------ |
| Complete records with valid types                           | `true`                                                             |
| Central records completed by nodes                          | `true`, even if the central data is incomplete                     |
| Type errors, missing required fields, or unknown options    | Evaluation error                                                   |
| Additional definitions of read-only fields                  | Evaluation error                                                   |
| A declared `assertions` option containing a false assertion | Checked as ordinary schema data; NixOS assertions are not executed |

Errors retain the relevant option path, node name, and available source filenames. This includes definitions with priorities, ordering, `mkMerge`, explicit `lib.mkDefinition` locations, and submodule source files. A missing required value has an option path but no definition filename.

For example, an invalid port from node `service publisher` in `invalid-service.nix` identifies these facts:

```text
services.api.port
service publisher
invalid-service.nix
```

Use Nix's `--show-trace` flag for more evaluation context. Exact wording and line or column formatting can change with the Nixpkgs module system.
