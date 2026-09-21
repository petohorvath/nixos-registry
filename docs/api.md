# API reference

The flake exports `lib.mkRegistry`, a function that combines shared data from central modules and named participants; `nixosModules.default`, a static participant module; and `flakeModules.default`, a static flake-parts module for project-level registry settings and results. The consuming project supplies the option declarations and evaluates the participant configurations.

Start with the complete [README example](../README.md#quickstart). The [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules) explains the underlying `lib.evalModules` function.

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

| Argument         | Value                                                                                                                                 | Default                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `lib`            | Nixpkgs library that supplies the module system and option types                                                                      | Required                 |
| `schemaModules`  | List of modules that declare the shared options                                                                                       | Required                 |
| `participants`   | Attribute set of named, evaluated configurations                                                                                      | Required; `{ }` is valid |
| `centralModules` | List of modules that define values for the shared options                                                                             | `[ ]`                    |
| `specialArgs`    | Attribute set of arguments for schema and central module evaluation, including the schema within each participant's `registry` option | `{ }`                    |

### `lib`

Use the same Nixpkgs module-system revision for this argument and every participant. For NixOS, use the same `nixpkgs` input for `lib` and `nixpkgs.lib.nixosSystem`.

Root development inputs select the repository's tools and test baselines. The caller-supplied `lib` remains authoritative for registry evaluation. Extra libraries or module arguments required by the schema must be supplied by the consuming project.

Package selection is separate from module-system selection. A NixOS configuration can use a package from another Nixpkgs input while retaining its selected module system. The [NixOS example](examples.md#nixos) demonstrates this.

### Plain-import access

The constructor remains available without supplying or evaluating any development inputs:

```nix
mkRegistry = ((import ./flake.nix).outputs { }).lib.mkRegistry;
registry = mkRegistry {
  inherit lib participants schemaModules;
};
```

Use the same caller-provided `lib` for participant evaluation. A consumer can obtain the repository as a source-only flake input with `flake = false` and import its `flake.nix` this way; the [flake-parts example](examples.md#flake-parts-and-separate-source-repositories) demonstrates this.

Normal flake consumption can add the root development inputs to a consumer's lock graph. This packaging change supersedes the original v1 specification's input-free-flake promise; constructor arguments, defaults, and registry behavior are preserved. See the [migration notes](../CHANGELOG.md).

### `schemaModules`

Declare shared options at their own paths, such as `options.services`. The generated module places those options under `registry` in each participant. The [service schema](../examples/plain-nix/service-schema.nix) is a complete example with required fields and a derived endpoint.

Schema modules can declare types, defaults, and derived values. Keep the declarations, their structure, and their arguments independent of participant evaluation. Shared option declarations belong here; participant contributions cannot add them.

### `participants`

Each value must be an evaluated configuration that imports the returned `registry.module`, or a NixOS configuration using the [static module](#static-nixos-module). Both `nixpkgs.lib.nixosSystem` and `lib.evalModules` produce suitable results for the generated module. Pass the whole evaluation result, including its `options`, rather than only its `config` attribute.

The attribute name identifies the participant in diagnostics. It need not match a hostname, service name, or source repository. For example:

```nix
participants = {
  "metrics publisher" = nixpkgs.lib.nixosSystem {
    modules = [ registry.module ./server.nix ];
  };
};
```

An independently declared option named `registry` does not replace either supported module. A participant with a missing or incompatible option produces an error naming the participant and the required import.

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

| Attribute  | Value                                 | Use                                                                               |
| ---------- | ------------------------------------- | --------------------------------------------------------------------------------- |
| `module`   | Nix module                            | Import it in each participant to declare the typed `registry` option.             |
| `central`  | Attribute set of shared option values | Read data from the schema and central modules, without participant contributions. |
| `combined` | Attribute set of shared option values | Read data from the schema, central modules, and all participant contributions.    |
| `validate` | Boolean value, or an evaluation error | Demand all combined data. Valid data produces `true`.                             |

`validate` is a value, so use `registry.validate` without function arguments. Both data sets include schema defaults and derived values. Either can remain incomplete if its definitions lack required fields.

## Option paths and shared reads

### Static flake module

Import `inputs.nixos-registry.flakeModules.default` into a flake-parts configuration. It evaluates one shared registry with the enclosing evaluator's `lib` and exposes the following options on that configuration:

| Project option                     | Meaning                                                                          | Default                  |
| ---------------------------------- | -------------------------------------------------------------------------------- | ------------------------ |
| `registry.settings.schemaModules`  | Shared option declarations; lists from project modules concatenate.              | Required; `[ ]` is valid |
| `registry.settings.participants`   | Named, whole participant evaluation results, including `options`.                | Required; `{ }` is valid |
| `registry.settings.centralModules` | Central definitions; lists from project modules concatenate.                     | `[ ]`                    |
| `registry.settings.specialArgs`    | Arguments for schema and central evaluation, including the participant's schema. | `{ }`                    |
| `registry.central`                 | Read-only central data.                                                          | Computed                 |
| `registry.combined`                | Read-only combined data.                                                         | Computed                 |
| `registry.validate`                | Read-only explicit validation, returning `true` or raising an error.             | Computed                 |

Supply required settings explicitly, even when empty. Settings may be split across project modules. Distinct participant names and argument keys compose; each value is kept opaque and lazy. Multiple definitions of the same participant name or argument key at the same override priority fail when demanded, even if identical. Normal overrides such as `lib.mkDefault` and `lib.mkForce` select definitions before that check. Module lists retain definition origins, and conflicting central values use the schema's ordinary merge rules.

The caller constructs every participant, chooses its module arguments, and selects registry membership through `registry.settings.participants`. Configurations elsewhere in `flake.nixosConfigurations` are not automatically enrolled. Names need not match hostnames. Registry `specialArgs` does not replace the arguments passed separately to `nixosSystem`.

Import the static NixOS module in a common participant module and pass only `schemaModules` and `specialArgs` from the project settings, plus the three shared results:

```nix
# In a flake-parts module receiving { config, inputs, ... }:
commonModule = {
  imports = [ inputs.nixos-registry.nixosModules.default ];
  registry = {
    settings = {
      inherit (config.registry.settings) schemaModules specialArgs;
    };
    inherit (config.registry) central combined validate;
  };
};
```

The [complete usage example](examples.md#static-flake-module) shows both imports and participant construction. Align `flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs"` with the input used by `nixosSystem`, so the enclosing evaluator and participants use the same module-system revision. The producer's development input does not select registry semantics.

Project-level `registry` contains settings and results; schema contributions belong to the participants' direct `registry` paths. Their static interface reserves the names described below and excludes settings and results from contributions. Keep schema structure and settings independent of participant values, and do not choose imports from these configuration results. Reading a result demands only that value; importing the flake module does not install or force a validation check. Existing constructor-based [flake-check wiring](examples.md#flake-parts-and-separate-source-repositories) also applies to the explicit validation value. Flake-parts remains optional for constructor and ordinary-flake consumers.

### Static NixOS module

Import `inputs.nixos-registry.nixosModules.default` directly in each participating NixOS configuration. The import needs no constructor application. Configure the shared schema and supply the existing registry's results through options:

```nix
settings = {
  schemaModules = [ ./schema.nix ];
  specialArgs = { };
};
registry = inputs.nixos-registry.lib.mkRegistry (settings // {
  lib = inputs.nixpkgs.lib;
  participants = nixosConfigurations;
  centralModules = [ ./central.nix ];
});
commonModule = {
  imports = [ inputs.nixos-registry.nixosModules.default ];
  registry = {
    inherit settings;
    inherit (registry) central combined validate;
  };
};
```

Import `commonModule` when constructing each participant with `inputs.nixpkgs.lib.nixosSystem`. The caller chooses the participants and supplies one shared registry. The static module neither discovers participants nor performs shared aggregation. Flake-parts is optional; the [runnable ordinary-flake example](examples.md#static-nixos-module) uses this wiring.

| Participant option                | Meaning                                                                                        | Default            |
| --------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------ |
| `registry.settings.schemaModules` | Shared schema modules; supply the same modules to `mkRegistry`. Lists compose normally.        | Required           |
| `registry.settings.specialArgs`   | Schema arguments; supply the same arguments to `mkRegistry` for schema and central evaluation. | `{ }`              |
| `registry.central`                | Central data supplied from the shared registry.                                                | Required when read |
| `registry.combined`               | Combined data supplied from the shared registry.                                               | Required when read |
| `registry.validate`               | Explicit validation supplied from the shared registry.                                         | Required when read |

The three result options accept one definition each. `central` and `combined` retain the supplied values without recursively merging their data; `validate` is a Boolean. Reading `config.registry.validate` demands the supplied validation value. Importing the module alone does not demand validation. Configure `participants` and `centralModules` on the project-level constructor, rather than in participant settings.

The static module obtains its module-system library from the enclosing NixOS evaluator. Keep that evaluator and `mkRegistry.lib` on the same Nixpkgs revision. Schema `specialArgs` do not supply arguments to ordinary participant modules; continue using `nixosSystem.specialArgs` for those.

Contributions still use direct schema paths such as `registry.services.metrics.port`. Read the local value at `config.registry.services.metrics.port`, central data at `config.registry.central.services.metrics.port`, and combined data at `config.registry.combined.services.metrics.port`. Only contribution definitions enter shared data; settings, shared results, and completed local defaults are excluded.

The complete library-reserved name list for this static interface is **`settings`, `central`, `combined`, and `validate`**, immediately beneath `registry`. A schema declaring any of those names, including as an option group, fails with a reserved-name error. `schemaModules` is permitted as a schema field because its library setting is nested beneath `settings`. The usual `_module` controls also remain unavailable for contributions. These restrictions do not apply to the constructor's generated module: existing schemas using the four names remain supported there.

Keep schema structure and settings independent of participant values. Read shared results through `config.registry` after NixOS has assembled its imports; using these configuration values to choose those imports introduces a module-system cycle. For setup that needs independent central values or schema keys during import discovery, retain the constructor's explicit module-argument route described [below](#schema-and-central-data-during-participant-setup).

#### Properties at the static contribution root

Nix first selects definitions of the participant's whole `registry` option. A root override therefore selects the local settings and result wiring too. An ordinary common-module definition overrides a separate `registry = lib.mkDefault { ... };` contribution locally; `registry = lib.mkForce { ... };` discards ordinary wiring. Apply priorities to individual contribution fields when only those fields should change. For a whole-root override, include the wiring at the selected priority:

```nix
registry = lib.mkForce {
  inherit settings;
  inherit (sharedRegistry) central combined validate;
  backupDestinations.archive = {
    host = "replacement.example.test";
    port = 2222;
  };
};
```

Here `settings` contains the common schema configuration and `sharedRegistry` is the caller's constructor result. The root priority applies to the whole contribution during shared aggregation. Nested priorities apply within the contributions that remain; fields from discarded contributions cannot complete a selected partial record.

Collection removes settings and results from the selected definitions, including inside `mkMerge` and other definition properties. Plain definitions containing only that wiring do not become empty contributions: a participant that only reads shared data through the common module cannot suppress another source's default contribution. An explicitly empty contribution, such as a separate `registry = lib.mkForce { };`, still participates in whole-root selection. Preserve local wiring separately at the same priority when using it.

Properties retained beneath a root override remain deferred until ordinary priority selection. For example, `lib.mkDefault (lib.mkIf condition { ... })` must not evaluate `condition` when a stronger central contribution wins. The same applies to deferred merge fragments and definition payloads. These roots retain native selection behavior, including selecting an empty record when their content contributes no fields; they are not inspected early to identify wiring-only content. Put `mkIf` outside an override to make the whole root definition conditional. List ordering belongs on schema list fields; ordering the whole root retains the module system's native failure.

### Constructor-generated module

The schema determines the available shared options. The `registry` prefix is added only in participant configurations:

| Place                             | Example path                              | Meaning                                         |
| --------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| Schema module                     | `options.services`                        | Declare the shared option.                      |
| Central module                    | `services.metrics.port`                   | Define a shared value outside the participants. |
| Participant module                | `registry.services.metrics.port`          | Contribute a value from this participant.       |
| Participant's local configuration | `config.registry.services.metrics.port`   | Read this participant's own value.              |
| Registry passed as an argument    | `registry.central.services.metrics.port`  | Read the central value.                         |
| Registry passed as an argument    | `registry.combined.services.metrics.port` | Read the merged value.                          |

With the generated module, setting `registry.services.metrics.port` contributes data. Reading `registry.combined.services.metrics.port` reads shared data through the module argument. `config.registry` contains only the participant's local contribution evaluated against the schema.

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

The same split works with static NixOS participants. Using the common module from [static NixOS wiring](#static-nixos-module) with the partial-record schema, the caller can construct two participants:

```nix
# Pass this list as centralModules to the shared constructor:
centralModules = [ { backupDestinations.archive.host = "archive.example.test"; } ];

participants = {
  transport = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      commonModule
      ({ config, ... }: {
        nixpkgs.hostPlatform = "x86_64-linux";
        services.prometheus.port = 2222;
        registry.backupDestinations.archive.port = config.services.prometheus.port;
      })
    ];
  };
  paths = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      commonModule
      ({ config, ... }: {
        nixpkgs.hostPlatform = "x86_64-linux";
        registry.backupDestinations.archive.paths = [ "/documents" ];
        environment.etc."backup-command".text =
          config.registry.combined.backupDestinations.archive.command;
      })
    ];
  };
};
```

Combined data contains `host = "archive.example.test"`, `port = 2222`, `paths = [ "/documents" ]`, `endpoint = "archive.example.test:2222"`, and `command = "backup archive.example.test:2222"`. Both local records and central data remain incomplete, while `config.registry.validate` returns `true`. The [static consumer tests](../tests/modules/static-contributions.nix) evaluate this split with actual NixOS participants and compare the completed record with direct module evaluation.

Schema defaults apply once per shared evaluation, regardless of participant count. An explicit list definition, including `[ ]`, replaces its schema default. Multiple explicit lists merge normally. Derived values use the fields from that evaluation; read-only defaults in the combined data therefore use the combined fields. Additional definitions of read-only values fail under normal module rules.

## Override a field or a whole contribution

Ordinary lists merge. Equal scalar definitions agree; conflicting scalar definitions raise errors. Central definitions and participant definitions follow the same rules.

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

| List definition             | Order priority      |
| --------------------------- | ------------------- |
| `lib.mkBefore values`       | 500                 |
| Ordinary definition         | 1000                |
| `lib.mkAfter values`        | 1500                |
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

With the static NixOS module, read the same shared values through the participant's `config.registry`:

```nix
{ config, ... }: {
  registry.services.api.host = "api.${config.registry.combined.domain}";
  environment.etc."api-endpoint".text =
    config.registry.combined.services.api.endpoint;
}
```

Here the project's `registry.settings.centralModules` supplies `domain = "example.test"` and `services.api.port = 8443`. The local contribution at `config.registry.services.api.host` is `api.example.test`; its local port remains undefined. `config.registry.central.services.api.port` reads the central port, while `config.registry.combined.services.api.endpoint` reads the completed endpoint `api.example.test:8443`. `config.registry.validate` validates that completed record without requiring a complete local or central record.

An unrelated invalid contribution can remain unused while reading an independent combined field. Central reads do not collect participants. Supplying shared results through the common module does not itself force validation; importing either static module and reading unrelated configuration can leave the registry unevaluated. The [static consumer tests](../tests/modules/static-reads.nix) exercise these reads and explicit validation through both public modules.

Collection types can force related definitions during merging. In the [collection example](../examples/plain-nix/collection-laziness.nix), both values are under one `settings` option:

```nix
# In a central module:
settings.domain = "example.test";

# In a participant module:
registry.settings.endpoint = "api.${registry.combined.settings.domain}:8443";
```

| Type of `settings`                    | Result with both tested Nixpkgs revisions                                                                             |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `lib.types.attrsOf lib.types.str`     | Reading the domain or validating recurses. Merging inspects the endpoint definition, which reads the same collection. |
| `lib.types.lazyAttrsOf lib.types.str` | Both values evaluate, and validation returns `true`.                                                                  |

The complete schema determines what gets evaluated. For example, `attrsOf (submodule ...)` in the combined-read example keeps the fields within each service record lazy. `lazyAttrsOf` has its own [limitations with conditional definitions](https://nixos.org/manual/nixos/stable/#sec-option-types-composed).

The static interfaces preserve this distinction between strict and lazy collections. Use a schema field such as `endpoints` for the same example through static modules: the constructor example's `settings` name is reserved by the static interface. Shared result options do not remove schema-induced strictness or resolve value cycles.

Lazy collections do not resolve value cycles. If one service reads a second service and the second reads the first, shared reads and validation can raise Nix's `infinite recursion encountered` error. The [value-cycle example](../examples/plain-nix/value-cycle.nix) demonstrates this.

### Schema and central data during participant setup

Both data sets get their top-level keys from the schema. Listing those keys does not evaluate central definitions or collect participant contributions:

```nix
builtins.attrNames registry.central
builtins.attrNames registry.combined
```

With the constructor, participants can inspect these keys through caller-supplied module arguments when selecting module imports. They can also read available `registry.central` values without collecting participant contributions. Static participants read `config.registry.central` and `config.registry.combined` after imports are assembled; using those participant configuration values to select the same imports causes a module-system cycle, even for an independent central value.

Keep schema declarations, their structure, and their arguments independent of participant evaluation. Central values used to set up a participant must also have independent dependencies. A central definition that reads participant data can cause recursion.

## Validation and diagnostics

`registry.validate` evaluates all combined data. Valid data returns `true`; invalid data raises a Nix evaluation error. It does not separately require every local or central record to be complete.

To make constructor validation part of a flake check, use this pattern with a package set for the selected `system`:

```nix
checks.${system}.registry =
  assert registry.validate;
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
      assert shared.validate;
      pkgs.runCommand "registry-validation" { } ''
        touch "$out"
      '';
  };
}
```

Run `nix build --no-update-lock-file --no-link .#checks.x86_64-linux.registry` for this check alone. Evaluating the check demands complete combined data and reports schema errors before a derivation can build. Defining the check leaves ordinary reads lazy; neither static module installs or demands a validation check automatically. The [static example](examples.md#static-flake-module) includes this wiring. Full `nix flake check --no-update-lock-file` also validates other consumer outputs, so exported NixOS configurations must include their machine-specific boot and filesystem settings.

| Combined data                                               | Result                                                             |
| ----------------------------------------------------------- | ------------------------------------------------------------------ |
| Complete records with valid types                           | `true`                                                             |
| Central records completed by participants                   | `true`, even if the central data is incomplete                     |
| Type errors, missing required fields, or unknown options    | Evaluation error                                                   |
| Additional definitions of read-only fields                  | Evaluation error                                                   |
| A declared `assertions` option containing a false assertion | Checked as ordinary schema data; NixOS assertions are not executed |

Errors retain the relevant option path, participant name, and available source filenames. This includes definitions with priorities, ordering, `mkMerge`, explicit `lib.mkDefinition` locations, and submodule source files. A missing required value has an option path but no definition filename.

For example, an invalid port from participant `service publisher` in `invalid-service.nix` identifies these facts:

```text
services.api.port
service publisher
invalid-service.nix
```

Use Nix's `--show-trace` flag for more evaluation context. Exact wording and line or column formatting can change with the Nixpkgs module system.
