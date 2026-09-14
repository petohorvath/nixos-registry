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

The tested contract covers the minimal standalone API in [issue #3](https://github.com/petohorvath/nixos-registry/issues/3) and independent schema discovery and central reads in [issue #4](https://github.com/petohorvath/nixos-registry/issues/4). The [v1 specification](https://github.com/petohorvath/nixos-registry/issues/1) tracks the remaining work. Partial records, preservation of whole-contribution priorities and ordering, broader laziness and validation guarantees, NixOS integration, and consumer migration have separate follow-up issues.

The underlying evaluation interface is documented in the [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules).
