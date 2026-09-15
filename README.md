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

Every participant imports the returned `registry.module`. Missing or incompatible contribution options report the collection key and the required import. An independently declared option named `registry` does not provide the generated interface.

Central and participant definitions are evaluated together under the shared schema. Ordinary lists merge, matching scalar definitions agree, and conflicting scalar definitions raise errors. No infrastructure schema or participant builder is bundled with the library.

## NixOS participants

The [NixOS example](examples/nixos/default.nix) builds two NixOS configurations using the caller-owned [service schema](examples/plain-nix/service-schema.nix). The same `nixpkgs` input supplies `mkRegistry.lib` and `nixpkgs.lib.nixosSystem`.

The caller imports the generated module and supplies the handle and participant-specific arguments:

```nix
participants."metrics publisher" = nixpkgs.lib.nixosSystem {
  specialArgs = {
    inherit registry;
    serviceName = "metrics";
  };
  modules = [
    registry.module
    ./publish-service.nix
    {
      nixpkgs.hostPlatform = "x86_64-linux";
      networking.hostName = "monitor";
      services.prometheus = {
        enable = true;
        port = 9191;
      };
      system.stateVersion = "26.05";
    }
  ];
};
```

The example's [publication module](examples/nixos/publish-service.nix) reads the combined domain and publishes the service's configured port:

```nix
networking.domain = registry.combined.domain;
registry.services.${serviceName} = lib.mkIf config.services.prometheus.enable {
  host = "${config.networking.hostName}.${config.networking.domain}";
  port = config.services.prometheus.port;
};
environment.etc."metrics-endpoint".text = registry.combined.services.metrics.endpoint;
```

The active participant publishes `metrics` at `monitor.example.test:9191`. The standby participant's disabled service contributes no record. Both configurations read the completed endpoint into `/etc/metrics-endpoint`, including the participant publishing its port. Collection keys, hostnames, and service names remain distinct.

Every participant in a registry uses the same Nixpkgs module-system revision as the constructor's `lib`. Package selection can use another package set. With the development inputs, the example accepts an alternate Prometheus package:

```nix
import ./examples/nixos {
  nixpkgs = inputs.nixpkgsStable;
  mkRegistry = inputs.registry.lib.mkRegistry;
  package = inputs.nixpkgsUnstable.legacyPackages.x86_64-linux.prometheus;
}
```

The `package` argument sets `services.prometheus.package`; `nixpkgs.lib.nixosSystem` still selects the module system. Mixing module-system revisions within a registry is unsupported. Tests exercise each pinned module revision separately, including a service command using the other pin's package.

The example returns `registry`, the participant evaluations, and a JSON-compatible `result` containing both views, client endpoints, and explicit validation. It defaults to `x86_64-linux`; the `system` argument selects another NixOS platform. Checks evaluate registry data and affected NixOS options without building a system closure or booting a VM.

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

## Ordering and conditional contributions

List ordering applies across central and participant definitions. Override priorities select the surviving definitions before ordering takes effect.

| List definition | Order priority |
| --- | --- |
| `lib.mkBefore paths` | 500 |
| Ordinary definition | 1000 |
| `lib.mkAfter paths` | 1500 |
| `lib.mkOrder number paths` | The supplied number |

Lower numbers come first. Ordering wrappers on the whole typed `registry` root fail with the pinned stable and unstable module libraries. The registry preserves that direct-evaluation failure; list ordering uses nested options such as `registry.backupDestinations.archive.paths`.

The [conditional-ordering example](examples/plain-nix/conditional-ordering.nix) controls publication with the participant's local `backup.enable` option:

```nix
registry = lib.mkIf config.backup.enable (
  lib.mkMerge [
    { backupDestinations.archive.paths = lib.mkBefore config.backup.paths; }
    { backupDestinations.archive.paths = lib.mkAfter [ "/srv/snapshots" ]; }
  ]
);
```

When enabled, the participant's paths surround the central paths:

```nix
[ "/srv/documents" "/srv/central" "/srv/snapshots" ]
```

When disabled, only `[ "/srv/central" ]` remains. The example also demonstrates a nested condition and a participant command that reads the combined result. Both variants explicitly validate the combined data.

Whole-contribution and nested conditions follow ordinary module semantics. Disabled or overridden contributions do not force discarded content beyond direct-evaluation behavior. `lib.mkMerge` composes conditional fragments without completing each local record first.

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

## Combined reads and schema forcing

The [combined-read example](examples/plain-nix/combined-reads.nix) publishes a service host using a centrally supplied domain from the combined view:

```nix
registry.services.api.host = "api.${registry.combined.domain}";
clientEndpoint = registry.combined.services.api.endpoint;
```

Central data supplies port `8443`. The shared evaluation completes the participant's partial record and derives endpoint `api.example.test:8443`. Reading the combined domain does not demand the missing local port.

Ordinary reads leave unrelated invalid data unused where the schema permits. For example, an invalid service port does not prevent reading the independent domain. Demanding the invalid field raises its evaluation error.

Collection types can force sibling definitions. An acyclic intended data-reference graph alone does not guarantee successful evaluation. The [collection-laziness example](examples/plain-nix/collection-laziness.nix) puts both values under one `settings` option:

```nix
# Central declaration
settings.domain = "example.test";

# Participant publication
registry.settings.endpoint = "api.${registry.combined.settings.domain}:8443";
```

| Type of `settings` | Result on both pinned module libraries |
| --- | --- |
| `lib.types.attrsOf lib.types.str` | Reading the domain or validating recurses: merging inspects the endpoint definition, which requests the same collection |
| `lib.types.lazyAttrsOf lib.types.str` | Both values evaluate, and validation returns `true` |

Forcing depends on the complete schema, including element types. The combined-read example uses `attrsOf (submodule ...)`, which keeps service fields lazy within their records. `lazyAttrsOf` retains the module system's [conditional-definition limitations](https://nixos.org/manual/nixos/stable/#sec-option-types-composed).

The [value-cycle example](examples/plain-nix/value-cycle.nix) has two participants: `services.east` reads `services.west`, and `services.west` reads `services.east`. Even with `lazyAttrsOf`, reads and validation raise Nix's native `infinite recursion encountered` error.

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

## Validation and diagnostics

`registry.validate` forces the complete combined data and returns `true` or raises an evaluation error. Checks explicitly demand it:

```nix
checks.${system}.registry =
  assert registry.validate;
  pkgs.runCommand "registry-validation" { } ''
    touch "$out"
  '';
```

| Combined data | Validation result |
| --- | --- |
| Complete, valid records | `true` |
| Central records completed by participants | `true`; the central view may remain incomplete |
| Unused type errors, missing required fields, or unknown options | Evaluation error |
| Additional definitions of read-only fields | Evaluation error |
| A declared `assertions` field containing a false assertion | Ordinary schema-checked data; no NixOS assertion execution |

Ordinary reads retain normal module-system laziness. Reading an independent valid field does not validate unused fields; the explicit check catches their errors.

Diagnostics retain the relevant option path, participant collection key, and available source filenames, including definitions with priorities, ordering, and `mkMerge`. Explicit `lib.mkDefinition` locations and submodule source files retain their origin alongside the participant name. A missing required value identifies its option path; an absent definition has no source filename.

For example, an invalid port from participant `service publisher` in `invalid-service.nix` identifies all three diagnostic facts:

```text
services.api.port
service publisher
invalid-service.nix
```

Nix's `--show-trace` flag includes surrounding evaluation context. Exact error wording, line numbers, and column formatting are not compatibility promises.

## Examples and checks

Commands run from the repository root with Nix's `nix-command` and `flakes` features enabled. Dependencies for examples, formatting, and evaluation checks live in the separate [development flake](dev/flake.nix) and [lock file](dev/flake.lock).

```sh
nix eval ./dev#lib.examples.stable --json
nix eval ./dev#lib.examples.unstable --json
nix eval ./dev#lib.examples.stable.validate
```

The NixOS example and its package-selection check run against both pinned module libraries:

```sh
nix eval ./dev#lib.nixosExamples.stable --json
nix eval ./dev#lib.nixosExamples.unstable --json
nix eval ./dev#lib.nixosExamples.stable.validate
nix eval ./dev#lib.tests.stable.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
nix eval ./dev#lib.tests.unstable.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
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

The conditional-ordering example exposes enabled and disabled publication with their combined data and derived commands:

```sh
nix eval ./dev#lib.conditionalOrdering.stable --json
nix eval ./dev#lib.conditionalOrdering.unstable --json
nix eval ./dev#lib.conditionalOrdering.stable.enabled.validate
```

The combined-read example exposes the completed service record, local host, derived client endpoint, and validation:

```sh
nix eval ./dev#lib.combinedReads.stable --json
nix eval ./dev#lib.combinedReads.unstable --json
```

The lazy collection variant also evaluates successfully:

```sh
nix eval ./dev#lib.collectionLaziness.stable.lazy --json
nix eval ./dev#lib.collectionLaziness.unstable.lazy --json
```

The strict collection variant and actual value cycle are expected to fail with native recursion errors:

```sh
nix eval ./dev#lib.collectionLaziness.stable.strict.combined.settings.domain
nix eval ./dev#lib.collectionLaziness.unstable.strict.combined.settings.domain
nix eval ./dev#lib.valueCycles.stable.combined.services.east
nix eval ./dev#lib.valueCycles.unstable.combined.services.east
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

Whole-root ordering failures run in separate Nix processes because `builtins.tryEval` cannot catch the selected libraries' native type error. These checks cover before, after, and explicit ordering in both central and participant contributions, including central reads and combined validation.

Recursion checks also run in separate Nix processes. Both pinned module libraries must report native recursion for strict collection forcing and actual value cycles, during shared reads and validation.

Diagnostic checks run in separate Nix processes on both pinned module libraries. They assert evaluation failure and stable facts such as option paths, collection keys, and source filenames, without matching complete error messages.

Formatting runs from the development flake directory:

```sh
cd dev
nix fmt -- ../flake.nix flake.nix ../lib/*.nix ../tests/*.nix ../examples/*/*.nix
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
- Ordering and conditional contributions in [issue #7](https://github.com/petohorvath/nixos-registry/issues/7).
- Combined reads, laziness, and native recursion behavior in [issue #8](https://github.com/petohorvath/nixos-registry/issues/8).
- Complete combined validation and source diagnostics in [issue #9](https://github.com/petohorvath/nixos-registry/issues/9).
- Real NixOS participants, caller-owned wiring, and independent package selection in [issue #10](https://github.com/petohorvath/nixos-registry/issues/10).

The [v1 specification](https://github.com/petohorvath/nixos-registry/issues/1) tracks the remaining examples and consumer migration.

The underlying evaluation interface is documented in the [Nixpkgs module-system reference](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules).
