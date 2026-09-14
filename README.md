# nixos-registry

`nixos-registry` combines typed shared data from central declarations and named Nix module evaluations. The caller owns the schema, participant construction, and module arguments. The consumer-facing flake has zero required inputs and exports `lib.mkRegistry`.

This registry concerns shared configuration data; Nix's flake registry concerns flake-name lookup. Participants can be plain Nix module evaluations without a NixOS hostname or system configuration.

## Constructor

```nix
registry = inputs.nixos-registry.lib.mkRegistry {
  inherit lib participants;
  schemaModules = [ ./schema.nix ];
  centralModules = [ ./central.nix ];
  specialArgs = { };
};
```

| Input | Meaning | Default |
| --- | --- | --- |
| `lib` | Caller's Nixpkgs module library, including schema-specific extensions | Required |
| `schemaModules` | Modules declaring relative shared options, such as `options.backupDestinations` | Required |
| `participants` | Named module evaluations that import `registry.module` | Required; `{ }` is valid |
| `centralModules` | Central definitions against the relative shared schema | `[ ]` |
| `specialArgs` | Arguments for schema and central-data module evaluation | `{ }` |

| Output | Meaning |
| --- | --- |
| `module` | Generic module declaring the typed `registry` contribution option |
| `central` | Data evaluated from the schema and central declarations alone |
| `combined` | Data evaluated from the schema, central declarations, and participant contributions |
| `validate` | Forces combined data and returns `true`, or raises a Nix evaluation error |

The caller selects the Nixpkgs module-system revision. All participants in one registry must use that revision. Schema-specific libraries and other arguments remain caller-owned.

## Publication and shared reads

```nix
participants."offsite backup job" = lib.evalModules {
  specialArgs = { inherit registry; };
  modules = [
    registry.module
    {
      registry.backupDestinations.offsite = {
        host = "offsite.example.test";
        port = 2222;
      };
    }
  ];
};
```

The collection key identifies the participant. `config.registry` contains that participant's local contribution. Shared reads use the supplied handle's `registry.central` or `registry.combined` view. Constructor `specialArgs` does not configure participant arguments; the participant builder supplies them separately.

Central and participant definitions are evaluated together under the shared schema. Ordinary lists merge, matching scalar definitions agree, and conflicting scalar definitions raise errors. No infrastructure schema or participant builder is bundled with the library.

## Contribution priorities

Whole-contribution priorities select definitions at the typed `registry` root before nested options merge. Weaker contributions are discarded in full, including unrelated fields. Central definitions and participant contributions have equal precedence unless an explicit priority changes it.

| Definition | Override priority |
| --- | --- |
| `lib.mkForce value` | 50 |
| Ordinary definition | 100 |
| `lib.mkDefault value` | 1000 |
| `lib.mkOverride number value` | The supplied number |

The lowest number wins. Definitions with equal priorities merge according to their option types; conflicting scalar values still fail. Nested priorities take effect only within the surviving contributions.

```nix
# Replaces weaker contributions, including their other backup destinations.
registry = lib.mkForce {
  backupDestinations.archive = {
    host = "replacement.example.test";
    port = 2222;
  };
};

# Overrides only the port when contribution-wide priorities are equal.
registry.backupDestinations.archive.port = lib.mkForce 2222;
```

The [priority example](examples/plain-nix/priorities.nix) evaluates these alternatives separately. Its whole-contribution default yields to the central definitions. Its forced contribution removes the central `offsite` destination and the archive's central paths. Its nested port override preserves both destinations and the central paths.

Central modules express a contribution-wide priority with `config = lib.mkForce { ... };` or another override property. A module containing only imports adds no contribution. The central view continues to evaluate central modules alone; participant overrides affect only the combined view.

Required fields in a discarded contribution cannot complete a surviving partial record. Schema defaults still apply in the shared evaluation. Errors retain participant collection keys and available source filenames; exact diagnostic wording is not a compatibility promise.

## Partial contributions, defaults, and derived values

Different sources can supply required fields of the same record. The [partial-contribution example](examples/plain-nix/partial-contributions.nix) completes `archive` from a central host and a participant's port. Two participants supply the host and port for `offsite`.

The example's [schema](examples/plain-nix/partial-schema.nix) supplies a list default, a read-only endpoint, and a derived backup command. Its completed `archive` record is:

```nix
{
  host = "archive.example.test";
  port = 2222;
  paths = [ "/srv/default" ];
  endpoint = "archive.example.test:2222";
  command = "backup archive.example.test:2222";
}
```

Local `config.registry` remains a schema-evaluated contribution. Its supplied fields are readable, but demanding a missing required field or a derived value that needs it fails. Collection reads definitions without demanding complete local records. Shared consumers read completed data from `registry.combined`.

The example reads only the available host from `registry.central`; its central record lacks a port. Combined validation succeeds once participants supply the missing fields. Demanding an incomplete combined record or forcing its `validate` fails.

Schema defaults apply once per shared evaluation, regardless of participant count. An explicit list definition, including `[ ]`, replaces its schema default; multiple explicit lists merge normally. Derived values and read-only defaults use the combined fields. Additional definitions of read-only values fail under ordinary module semantics.

## Schema and evaluation independence

Both views derive their top-level keys from the options declared in `schemaModules`. Additional schema modules extend that set; no separate key list is needed. Inspecting those keys does not evaluate central definitions or collect participant contributions:

```nix
builtins.attrNames registry.central
builtins.attrNames registry.combined
```

Participants can inspect these keys when selecting module imports. Reading available `registry.central` data also works during participant construction, even when collecting contributions would fail. Reading a combined value collects contributions as needed; `validate` demands the complete combined evaluation.

Schema declarations, their structure, and their arguments must remain independent of participant evaluation. Central definitions used during participant construction must also have independent dependencies. A central definition that reads participant-derived data can still recurse.

Participants can add entries beneath declared collection options without central entry declarations. Publications cannot install shared option declarations, including through submodule functions or imports. Data-only submodule functions retain their module arguments. Module controls under `registry._module` are reserved, and unrestricted freeform registry roots are rejected. Collection types and any freeform data beneath declared options remain caller-owned.

The [plain Nix example](examples/plain-nix/default.nix) owns its [backup schema](examples/plain-nix/schema.nix) and builds two participants. One publishes its configured port and reads both shared views. Central and participant paths for the archive merge to:

```nix
[ "/srv/central" "/srv/documents" ]
```

## Examples and checks

Commands run from the repository root with Nix's `nix-command` and `flakes` features enabled. Dependencies for examples, formatting, and evaluation checks live in the separate [development flake](dev/flake.nix) and [lock file](dev/flake.lock).

```sh
nix eval ./dev#lib.examples.stable --json
nix eval ./dev#lib.examples.unstable --json
nix eval ./dev#lib.examples.stable.validate
```

The partial-contribution example exposes completed records, the available central host, and the transport participant's local port:

```sh
nix eval ./dev#lib.partialContributions.stable --json
nix eval ./dev#lib.partialContributions.unstable --json
nix eval ./dev#lib.partialContributions.stable.validate
```

The priority example exposes whole-contribution defaults, whole-contribution forcing, and a nested port override:

```sh
nix eval ./dev#lib.priorities.stable --json
nix eval ./dev#lib.priorities.unstable --json
nix eval ./dev#lib.priorities.stable.forcedContribution.validate
```

The [scalar-conflict example](examples/plain-nix/scalar-conflict.nix) assigns different archive hosts centrally and in a participant. Both commands below are expected to exit unsuccessfully with an error for `backupDestinations.archive.host`:

```sh
nix eval ./dev#lib.scalarConflicts.stable
nix eval ./dev#lib.scalarConflicts.unstable
```

Focused test and separate channel runs:

```sh
nix eval ./dev#lib.tests.stable.testCollectsCentralAndNamedParticipants
nix eval ./dev#lib.tests.stable --json
nix eval ./dev#lib.tests.unstable --json
```

The complete suite runs both module libraries on the current system:

```sh
nix flake check ./dev
```

Tests exercise the exported constructor, generated module, and returned views through real module evaluations. Merge checks compare observable results with direct evaluation using the same library. Nix evaluates option types during these checks; no separate static typechecker is configured. The suite includes the successful example and expected scalar-conflict failure.

Formatting runs from the development flake directory:

```sh
cd dev
nix fmt -- ../flake.nix flake.nix ../lib/*.nix ../tests/*.nix ../examples/plain-nix/*.nix
```

The checked-in dependency selections are:

| Run | Nixpkgs branch | Revision |
| --- | --- | --- |
| Stable | `nixos-26.05` | `c3eea5b2156db11c7eeeada3dc737711255b253e` |
| Unstable | `nixos-unstable` | `ef34387ddd751e1ab8857adf4676492d32eb24ec` |

## Implementation status

The tested contract includes:

- The minimal standalone API in [issue #3](https://github.com/petohorvath/nixos-registry/issues/3).
- Independent schema discovery and central reads in [issue #4](https://github.com/petohorvath/nixos-registry/issues/4).
- Partial records, defaults, and derived values in [issue #5](https://github.com/petohorvath/nixos-registry/issues/5).
- Whole-contribution and nested override priorities in [issue #6](https://github.com/petohorvath/nixos-registry/issues/6).

The [v1 specification](https://github.com/petohorvath/nixos-registry/issues/1) tracks ordering, broader laziness and validation guarantees, NixOS integration, and consumer migration.

The underlying evaluation interface is documented in the [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules).
