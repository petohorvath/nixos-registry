# Examples

The [README](../README.md#quickstart) contains a complete flake with two NixOS configurations sharing a service address. The examples below cover other ways to use the same API.

Run commands from the repository root with Nix's `nix-command` and `flakes` features enabled. The [root flake](../flake.nix) uses the `nixpkgs` selection in [flake.lock](../flake.lock). The [development guide](development.md#compatibility-checks) explains how the policy runner checks these examples against both shared revisions.

## NixOS

The [NixOS example](../examples/nixos/default.nix) uses the [service schema](../examples/plain-nix/service-schema.nix) and a [module that contributes service data](../examples/nixos/publish-service.nix).

The configuration named `metrics publisher` enables Prometheus and contributes its actual configured port. The configuration named `standby publisher` disables Prometheus and contributes no service record. Both read the combined endpoint into `/etc/metrics-endpoint`.

```sh
nix eval --no-update-lock-file .#lib.nixosExamples.x86_64-linux --json
nix eval --no-update-lock-file .#lib.nixosExamples.x86_64-linux.validate
```

The `clientEndpoints` result contains `monitor.example.test:9191` for both participants. `combined.services` contains `metrics` and no `standby` entry. The participant names, hostnames, and service names serve different purposes.

The example function takes `nixpkgs` and `mkRegistry`. It returns `registry`, `participants`, and a `result` attribute set that can be evaluated as JSON. The `system` argument defaults to `x86_64-linux`. These are configuration evaluations; the checks do not build a NixOS system or boot a VM.

An optional `package` argument selects the Prometheus package. A caller that declares an additional `nixpkgs-unstable` input can use it for the package while keeping the selected module system:

```nix
import ./examples/nixos {
  nixpkgs = inputs.nixpkgs;
  mkRegistry = inputs.self.lib.mkRegistry;
  package = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.prometheus;
}
```

This changes `services.prometheus.package`. The caller's `nixpkgs` input still selects the module system through `nixpkgs.lib.nixosSystem`. Every participant and the registry must use the same module-system revision. The repository's root flake has only the selected `nixpkgs` input; its alternate-package test uses an extended package set from that revision.

## Plain Nix modules

The [plain Nix example](../examples/plain-nix/default.nix) uses `lib.evalModules` with a [backup-destination schema](../examples/plain-nix/schema.nix). It has two participants, with no NixOS configuration or hostname requirement.

Each participant imports `registry.module`. A participant that reads shared data receives `registry` through its `specialArgs`. One contributes its configured port and reads both central and combined data.

```sh
nix eval --no-update-lock-file .#lib.examples --json
nix eval --no-update-lock-file .#lib.examples.validate
```

The result includes central and combined data, validation, and the command `backup archive.example.test local.example.test`. The combined archive paths are `[ "/srv/central" "/srv/documents" ]`.

## Flake-parts and separate source repositories

The [flake-parts example](../examples/flake-parts/flake.nix) defines its own [schema](../examples/flake-parts/schema.nix) and [participant evaluations](../examples/flake-parts/module.nix). Two source flakes export generic modules:

| Source                                                               | Contribution                               | Shared data it reads                                                    |
| -------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| [Service publisher](../examples/sources/service-publisher/flake.nix) | API hostname and configured port `8443`    | `registry.combined.domain`                                              |
| [Backup client](../examples/sources/backup-client/flake.nix)         | Backup hostname and configured port `8022` | `registry.central.domain` and `registry.combined.services.api.endpoint` |

The example uses local path inputs for the source flakes. Locked repository URLs can replace those paths without changing the modules. The consuming flake evaluates both source modules with its selected `lib`:

```nix
participants = {
  "api publisher" = mkParticipant inputs.servicePublisher.modules.generic.default;
  "backup consumer" = mkParticipant inputs.backupClient.modules.generic.default;
};

mkParticipant = participantModule: lib.evalModules {
  specialArgs = { inherit registry; };
  modules = [ registry.module participantModule ];
};
```

The backup command becomes `backup --api api.example.test:8443`. Each local `config.registry.services` contains only that participant's service. `registry.combined.services` contains both services.

Flake-parts' `nixpkgs-lib` input follows the example's `nixpkgs` input. Flake-parts, the registry, and the participants therefore use the same module-system revision. The registry input uses `flake = false` and imports the public constructor from its source. This keeps the example independent of the registry's development input graph, including when the root suite evaluates the example. The standalone lock contains only the example's own dependency graph; its separate participant source inputs remain intact.

Run the example directly with its own lock file:

```sh
nix eval --no-update-lock-file ./examples/flake-parts#lib.result --json
nix eval --no-update-lock-file ./examples/flake-parts#lib.result.validate
nix flake check --no-update-lock-file ./examples/flake-parts
```

The composition module also exposes validation through `perSystem.checks`. The root suite assembles the same example with its selected `nixpkgs` and the flake-parts source pinned by the example lock. Separate-source participant assertions and exact example results run under each policy compatibility override as well as the committed root selection:

```sh
nix eval --no-update-lock-file .#lib.flakePartsExamples --json
```

## Specific behavior

These examples make merge rules and evaluation behavior visible in their results. Each uses the selected root input. The [API reference](api.md) explains the rules.

| Example                                                                        | Command                                                               | Result to inspect                                                                                           |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [Partial contributions](../examples/plain-nix/partial-contributions.nix)       | `nix eval --no-update-lock-file .#lib.partialContributions --json`    | Completed records from different sources, schema defaults, derived values, and the fields available locally |
| [Override priorities](../examples/plain-nix/priorities.nix)                    | `nix eval --no-update-lock-file .#lib.priorities --json`              | A default contribution, a forced contribution, and an override of one port                                  |
| [Conditions and list ordering](../examples/plain-nix/conditional-ordering.nix) | `nix eval --no-update-lock-file .#lib.conditionalOrdering --json`     | Enabled contributions around the central paths; central paths alone when disabled                           |
| [Combined reads](../examples/plain-nix/combined-reads.nix)                     | `nix eval --no-update-lock-file .#lib.combinedReads --json`           | A contributed host using the shared domain, completed with the central port                                 |
| [Lazy collection](../examples/plain-nix/collection-laziness.nix)               | `nix eval --no-update-lock-file .#lib.collectionLaziness.lazy --json` | Domain and endpoint under a `lazyAttrsOf` option, with successful validation                                |

To demand validation separately, use the attribute exposed by the example:

```sh
nix eval --no-update-lock-file .#lib.partialContributions.validate
nix eval --no-update-lock-file .#lib.priorities.forcedContribution.validate
nix eval --no-update-lock-file .#lib.conditionalOrdering.enabled.validate
```

### Examples that intentionally fail

The [scalar-conflict example](../examples/plain-nix/scalar-conflict.nix) sets different archive hosts in a central module and a participant. This command fails with an error for `backupDestinations.archive.host`:

```sh
nix eval --no-update-lock-file .#lib.scalarConflicts
```

The strict variant of the [collection example](../examples/plain-nix/collection-laziness.nix) and the [value-cycle example](../examples/plain-nix/value-cycle.nix) fail with native recursion errors:

```sh
nix eval --no-update-lock-file .#lib.collectionLaziness.strict.combined.settings.domain
nix eval --no-update-lock-file .#lib.valueCycles.combined.services.east
```

Both policy compatibility runs check these failures too. They demonstrate limits of the schema or data dependencies and are expected test results.
