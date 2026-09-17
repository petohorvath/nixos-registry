# API reference

The flake exports `lib.mkRegistry`, a function that combines shared data from central modules and named participants. The consuming project supplies the option declarations and evaluates the participant configurations.

Start with the complete [README example](../README.md#quick-start). The [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules) explains the underlying `lib.evalModules` function.

## Call `mkRegistry`

The following call assumes that `schema.nix`, `central.nix`, and `nixosConfigurations` are defined by the consuming project:

```nix
registry = inputs.nixos-registry.lib.mkRegistry {
  lib = inputs.nixpkgs.lib;
  schemaModules = [ ./schema.nix ];
  participants = nixosConfigurations;
  centralModules = [ ./central.nix ];
  specialArgs = { };
};
```

The function takes one attribute set with these arguments:

| Argument | Value | Default |
| --- | --- | --- |
| `lib` | Nixpkgs library that supplies the module system and option types | Required |
| `schemaModules` | List of modules that declare the shared options | Required |
| `participants` | Attribute set of named, evaluated configurations | Required; `{ }` is valid |
| `centralModules` | List of modules that define values for the shared options | `[ ]` |
| `specialArgs` | Attribute set of arguments for schema and central module evaluation, including the schema within each participant's `registry` option | `{ }` |

### `lib`

Use the same Nixpkgs module-system revision for this argument and every participant. For NixOS, use the same `nixpkgs` input for `lib` and `nixpkgs.lib.nixosSystem`.

The library flake has no required inputs and does not select Nixpkgs. Extra libraries or module arguments required by the schema must be supplied by the consuming project.

Package selection is separate from module-system selection. A NixOS configuration can use a package from another Nixpkgs input while retaining its selected module system. The [NixOS example](examples.md#nixos) demonstrates this.

### `schemaModules`

Declare shared options at their own paths, such as `options.services`. The generated module places those options under `registry` in each participant. The [service schema](../examples/plain-nix/service-schema.nix) is a complete example with required fields and a derived endpoint.

Schema modules can declare types, defaults, and derived values. Keep the declarations, their structure, and their arguments independent of participant evaluation. Shared option declarations belong here; participant contributions cannot add them.

### `participants`

Each value must be an evaluated configuration that imports the returned `registry.module`. Both `nixpkgs.lib.nixosSystem` and `lib.evalModules` produce suitable results. Pass the whole evaluation result, including its `options`, rather than only its `config` attribute.

The attribute name identifies the participant in diagnostics. It need not match a hostname, service name, or source repository. For example:

```nix
participants = {
  "metrics publisher" = nixpkgs.lib.nixosSystem {
    modules = [ registry.module ./server.nix ];
  };
};
```

An independently declared option named `registry` does not replace the generated module. A participant with a missing or incompatible option produces an error naming the participant and the required import.

### `centralModules`

Define shared values directly against the schema, without the `registry` prefix. For example, a central module can set `services.metrics.port = 9090;` when the schema declares `services` with that field.

Central definitions have the same precedence as ordinary participant definitions. Use `lib.mkDefault`, `lib.mkForce`, or `lib.mkOverride` when a different precedence is needed.

### `specialArgs`

The `mkRegistry` argument supplies arguments to the schema and central module evaluations. It does not supply arguments to participant modules.

To let a NixOS participant read shared data, pass the registry to `nixosSystem` separately:

```nix
specialArgs = { inherit registry; };
modules = [
  registry.module
  ({ registry, ... }: {
    environment.etc."metrics-endpoint".text =
      registry.combined.services.metrics.endpoint;
  })
];
```

This example uses the `endpoint` field from the [service schema](../examples/plain-nix/service-schema.nix). Plain Nix participants use the same `specialArgs` pattern with `lib.evalModules`.

## Returned attributes

`mkRegistry` returns an attribute set with four attributes:

| Attribute | Value | Use |
| --- | --- | --- |
| `module` | Nix module | Import it in each participant to declare the typed `registry` option. |
| `central` | Attribute set of shared option values | Read data from the schema and central modules, without participant contributions. |
| `combined` | Attribute set of shared option values | Read data from the schema, central modules, and all participant contributions. |
| `validate` | Boolean value, or an evaluation error | Demand all combined data. Valid data produces `true`. |

`validate` is a value, so use `registry.validate` without function arguments. Both data sets include schema defaults and derived values. Either can remain incomplete if its definitions lack required fields.

## Option paths and shared reads

The schema determines the available shared options. The `registry` prefix is added only in participant configurations:

| Place | Example path | Meaning |
| --- | --- | --- |
| Schema module | `options.services` | Declare the shared option. |
| Central module | `services.metrics.port` | Define a shared value outside the participants. |
| Participant module | `registry.services.metrics.port` | Contribute a value from this participant. |
| Participant's local configuration | `config.registry.services.metrics.port` | Read this participant's own value. |
| Registry passed as an argument | `registry.central.services.metrics.port` | Read the central value. |
| Registry passed as an argument | `registry.combined.services.metrics.port` | Read the merged value. |

Setting `registry.services.metrics.port` in a module contributes data. Reading `registry.combined.services.metrics.port` reads shared data through the module argument. `config.registry` contains only the participant's local contribution evaluated against the schema.

Participants can add entries beneath declared collection options. For example, declaring a `services` option with `attrsOf (submodule ...)` allows a participant to add `services.metrics` without a central declaration for that entry.

Contributions cannot add shared option declarations, including through submodule functions or imports. Data-only submodule functions retain their normal module arguments. `registry._module` is reserved for module-system controls, and a freeform registry root is unsupported. Declared options can use collection types or freeform data within their own types.

## Partial records, defaults, and derived values

Different contributions can supply different required fields of one record. The shared evaluation merges the definitions before it evaluates the completed record.

For example, a central module can supply a host and a participant can supply its port:

```nix
# In a central module:
backupDestinations.archive.host = "archive.example.test";

# In a participant module:
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

The participant's local record still lacks a host. Its port can be read from `config.registry`, but reading its missing host or derived endpoint fails. The central record likewise lacks a port. Use `registry.combined` to read the completed record.

Schema defaults apply once per shared evaluation, regardless of participant count. An explicit list definition, including `[ ]`, replaces its schema default. Multiple explicit lists merge normally. Derived values use the fields from that evaluation; read-only defaults in the combined data therefore use the combined fields. Additional definitions of read-only values fail under normal module rules.

## Override a field or a whole contribution

Ordinary lists merge. Equal scalar definitions agree; conflicting scalar definitions raise errors. Central definitions and participant definitions follow the same rules.

Override priorities select which definitions remain:

| Definition | Override priority |
| --- | --- |
| `lib.mkForce value` | 50 |
| Ordinary definition | 100 |
| `lib.mkDefault value` | 1000 |
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

Central modules set a priority for the whole contribution with `config = lib.mkForce { ... };` or another override. A central module containing only imports adds no contribution of its own. Participant overrides affect `registry.combined`; `registry.central` still evaluates only central modules.

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

List ordering applies across central and participant definitions after override priorities select the definitions to keep:

| List definition | Order priority |
| --- | --- |
| `lib.mkBefore values` | 500 |
| Ordinary definition | 1000 |
| `lib.mkAfter values` | 1500 |
| `lib.mkOrder number values` | The supplied number |

Lower numbers come first. Apply ordering to nested list options. Ordering the whole `registry` option fails with both tested Nixpkgs revisions, as it does in direct module evaluation.

Whole contributions and nested values follow normal module conditions. Discarded definitions retain the module system's evaluation behavior. `lib.mkMerge` can combine partial records without first completing each local record.

## Evaluation and recursion

Reading one shared field does not evaluate all other fields. An invalid service port can remain unused while an independent domain value is read. `registry.validate` explicitly evaluates the complete combined data.

A contribution can read shared data when the schema and value dependencies permit it. The [combined-read example](../examples/plain-nix/combined-reads.nix) uses:

```nix
registry.services.api.host = "api.${registry.combined.domain}";
clientEndpoint = registry.combined.services.api.endpoint;
```

The central data supplies the domain and port. The combined data completes the record and derives its endpoint without demanding a complete local record.

Collection types can force related definitions during merging. In the [collection example](../examples/plain-nix/collection-laziness.nix), both values are under one `settings` option:

```nix
# In a central module:
settings.domain = "example.test";

# In a participant module:
registry.settings.endpoint = "api.${registry.combined.settings.domain}:8443";
```

| Type of `settings` | Result with both tested Nixpkgs revisions |
| --- | --- |
| `lib.types.attrsOf lib.types.str` | Reading the domain or validating recurses. Merging inspects the endpoint definition, which reads the same collection. |
| `lib.types.lazyAttrsOf lib.types.str` | Both values evaluate, and validation returns `true`. |

The complete schema determines what gets evaluated. For example, `attrsOf (submodule ...)` in the combined-read example keeps the fields within each service record lazy. `lazyAttrsOf` has its own [limitations with conditional definitions](https://nixos.org/manual/nixos/stable/#sec-option-types-composed).

Lazy collections do not resolve value cycles. If one service reads a second service and the second reads the first, shared reads and validation can raise Nix's `infinite recursion encountered` error. The [value-cycle example](../examples/plain-nix/value-cycle.nix) demonstrates this.

### Schema and central data during participant setup

Both data sets get their top-level keys from the schema. Listing those keys does not evaluate central definitions or collect participant contributions:

```nix
builtins.attrNames registry.central
builtins.attrNames registry.combined
```

Participants can inspect these keys when selecting module imports. They can also read available `registry.central` values without collecting participant contributions.

Keep schema declarations, their structure, and their arguments independent of participant evaluation. Central values used to set up a participant must also have independent dependencies. A central definition that reads participant data can cause recursion.

## Validation and diagnostics

`registry.validate` evaluates all combined data. Valid data returns `true`; invalid data raises a Nix evaluation error. It does not separately require every local or central record to be complete.

To make validation part of a flake check, use this pattern with a package set for the selected `system`:

```nix
checks.${system}.registry =
  assert registry.validate;
  pkgs.runCommand "registry-validation" { } ''
    touch "$out"
  '';
```

| Combined data | Result |
| --- | --- |
| Complete records with valid types | `true` |
| Central records completed by participants | `true`, even if the central data is incomplete |
| Type errors, missing required fields, or unknown options | Evaluation error |
| Additional definitions of read-only fields | Evaluation error |
| A declared `assertions` option containing a false assertion | Checked as ordinary schema data; NixOS assertions are not executed |

Errors retain the relevant option path, participant name, and available source filenames. This includes definitions with priorities, ordering, `mkMerge`, explicit `lib.mkDefinition` locations, and submodule source files. A missing required value has an option path but no definition filename.

For example, an invalid port from participant `service publisher` in `invalid-service.nix` identifies these facts:

```text
services.api.port
service publisher
invalid-service.nix
```

Use Nix's `--show-trace` flag for more evaluation context. Exact wording and line or column formatting can change with the Nixpkgs module system.
