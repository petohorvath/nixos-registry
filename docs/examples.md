# Examples

The [README](../README.md#quick-start) contains a complete flake with two NixOS configurations sharing a service address. The examples below cover other ways to use the same API.

Run commands from the repository root with Nix's `nix-command` and `flakes` features enabled. The [development flake](../dev/flake.nix) supplies the dependencies pinned in [dev/flake.lock](../dev/flake.lock). Commands using `.stable` also accept `.unstable` to select the other tested Nixpkgs revision.

## NixOS

The [NixOS example](../examples/nixos/default.nix) uses the [service schema](../examples/plain-nix/service-schema.nix) and a [module that contributes service data](../examples/nixos/publish-service.nix).

The configuration named `metrics publisher` enables Prometheus and contributes its actual configured port. The configuration named `standby publisher` disables Prometheus and contributes no service record. Both read the combined endpoint into `/etc/metrics-endpoint`.

```sh
nix eval ./dev#lib.nixosExamples.stable --json
nix eval ./dev#lib.nixosExamples.stable.validate
```

The `clientEndpoints` result contains `monitor.example.test:9191` for both participants. `combined.services` contains `metrics` and no `standby` entry. The participant names, hostnames, and service names serve different purposes.

The example function takes `nixpkgs` and `mkRegistry`. It returns `registry`, `participants`, and a `result` attribute set that can be evaluated as JSON. The `system` argument defaults to `x86_64-linux`. These are configuration evaluations; the checks do not build a NixOS system or boot a VM.

An optional `package` argument selects the Prometheus package. With the development flake's inputs, the call looks like this:

```nix
import ./examples/nixos {
  nixpkgs = inputs.nixpkgsStable;
  mkRegistry = inputs.registry.lib.mkRegistry;
  package = inputs.nixpkgsUnstable.legacyPackages.x86_64-linux.prometheus;
}
```

This changes `services.prometheus.package`. The stable input still selects the module system through `nixpkgs.lib.nixosSystem`. Every participant and the registry must use the same module-system revision.

## Plain Nix modules

The [plain Nix example](../examples/plain-nix/default.nix) uses `lib.evalModules` with a [backup-destination schema](../examples/plain-nix/schema.nix). It has two participants, with no NixOS configuration or hostname requirement.

Each participant imports `registry.module`. A participant that reads shared data receives `registry` through its `specialArgs`. One contributes its configured port and reads both central and combined data.

```sh
nix eval ./dev#lib.examples.stable --json
nix eval ./dev#lib.examples.stable.validate
```

The result includes central and combined data, validation, and the command `backup archive.example.test local.example.test`. The combined archive paths are `[ "/srv/central" "/srv/documents" ]`.

## Flake-parts and separate source repositories

The [flake-parts example](../examples/flake-parts/flake.nix) defines its own [schema](../examples/flake-parts/schema.nix) and [participant evaluations](../examples/flake-parts/module.nix). Two source flakes export generic modules:

| Source | Contribution | Shared data it reads |
| --- | --- | --- |
| [Service publisher](../examples/sources/service-publisher/flake.nix) | API hostname and configured port `8443` | `registry.combined.domain` |
| [Backup client](../examples/sources/backup-client/flake.nix) | Backup hostname and configured port `8022` | `registry.central.domain` and `registry.combined.services.api.endpoint` |

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

Flake-parts' `nixpkgs-lib` input follows the example's `nixpkgs` input. Flake-parts, the registry, and the participants therefore use the same module-system revision. The root library flake requires none of these example dependencies.

Run the example directly with its own lock file:

```sh
nix eval ./examples/flake-parts#lib.result --json
nix eval ./examples/flake-parts#lib.result.validate
nix flake check ./examples/flake-parts
```

The composition module also exposes validation through `perSystem.checks`. The development flake evaluates this example with each pinned Nixpkgs revision:

```sh
nix eval ./dev#lib.flakePartsExamples.stable --json
nix eval ./dev#lib.flakePartsExamples.unstable --json
```

## Specific behavior

These examples make merge rules and evaluation behavior visible in their results. Each command has a matching `.unstable` variant. The [API reference](api.md) explains the rules.

| Example | Command | Result to inspect |
| --- | --- | --- |
| [Partial contributions](../examples/plain-nix/partial-contributions.nix) | `nix eval ./dev#lib.partialContributions.stable --json` | Completed records from different sources, schema defaults, derived values, and the fields available locally |
| [Override priorities](../examples/plain-nix/priorities.nix) | `nix eval ./dev#lib.priorities.stable --json` | A default contribution, a forced contribution, and an override of one port |
| [Conditions and list ordering](../examples/plain-nix/conditional-ordering.nix) | `nix eval ./dev#lib.conditionalOrdering.stable --json` | Enabled contributions around the central paths; central paths alone when disabled |
| [Combined reads](../examples/plain-nix/combined-reads.nix) | `nix eval ./dev#lib.combinedReads.stable --json` | A contributed host using the shared domain, completed with the central port |
| [Lazy collection](../examples/plain-nix/collection-laziness.nix) | `nix eval ./dev#lib.collectionLaziness.stable.lazy --json` | Domain and endpoint under a `lazyAttrsOf` option, with successful validation |

To demand validation separately, use the attribute exposed by the example:

```sh
nix eval ./dev#lib.partialContributions.stable.validate
nix eval ./dev#lib.priorities.stable.forcedContribution.validate
nix eval ./dev#lib.conditionalOrdering.stable.enabled.validate
```

### Examples that intentionally fail

The [scalar-conflict example](../examples/plain-nix/scalar-conflict.nix) sets different archive hosts in a central module and a participant. This command fails with an error for `backupDestinations.archive.host`:

```sh
nix eval ./dev#lib.scalarConflicts.stable
```

The strict variant of the [collection example](../examples/plain-nix/collection-laziness.nix) and the [value-cycle example](../examples/plain-nix/value-cycle.nix) fail with native recursion errors:

```sh
nix eval ./dev#lib.collectionLaziness.stable.strict.combined.settings.domain
nix eval ./dev#lib.valueCycles.stable.combined.services.east
```

The same commands with `.unstable` also fail. These failures demonstrate limits of the schema or data dependencies; they are expected test results.
