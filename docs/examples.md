# Examples

The [README](../README.md#quickstart) contains a complete flake with two NixOS configurations sharing a service address. The examples below cover other ways to use the same API.

Run commands from the repository root with Nix's `nix-command` and `flakes` features enabled. The [root flake](../flake.nix) uses the `nixpkgs` selection in [flake.lock](../flake.lock). File commands use `examples/default.nix` with the root inputs and host system; `--impure` permits resolving the checkout path. Use `--argstr system aarch64-linux` to select another system. The [development guide](development.md#compatibility-checks) explains how the policy runner checks these examples against both shared revisions.

## NixOS

The [NixOS example](../examples/nixos/default.nix) uses the [service schema](../examples/plain-nix/service-schema.nix) and a [module that contributes service data](../examples/nixos/publish-service.nix).

The configuration named `metrics publisher` enables Prometheus and contributes its actual configured port. The configuration named `standby publisher` disables Prometheus and contributes no service record. Both read the combined endpoint into `/etc/metrics-endpoint`.

```sh
nix eval --impure --file examples nixos --json
nix eval --impure --file examples nixos.validate
```

The `clientEndpoints` result contains `monitor.example.test:9191` for both nodes. `combined.services` contains `metrics` and no `standby` entry. The node names, hostnames, and service names serve different purposes.

The example function takes `nixpkgs` and `mkRegistry`. It returns `registry`, `nodes`, and a `result` attribute set that can be evaluated as JSON. The `system` argument defaults to `x86_64-linux`. These are configuration evaluations; the checks do not build a NixOS system or boot a VM.

An optional `package` argument selects the Prometheus package. A caller that declares an additional `nixpkgs-unstable` input can use it for the package while keeping the selected module system:

```nix
import ./examples/nixos {
  nixpkgs = inputs.nixpkgs;
  mkRegistry = inputs.self.lib.mkRegistry;
  package = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.prometheus;
}
```

This changes `services.prometheus.package`. The caller's `nixpkgs` input still selects the module system through `nixpkgs.lib.nixosSystem`. Every node and the registry must use the same module-system revision. The repository's root flake has one `nixpkgs` selection; its alternate-package test uses an extended package set from that revision.

## Static NixOS module

The [ordinary-flake consumer](../examples/static-nixos/default.nix) imports the public `nixosModules.default` through a common NixOS module. It keeps one project-level `lib.mkRegistry` call and supplies the same schema through `registry.settings.schemaModules`. The common module assigns the shared registry's `central`, `combined`, and `validate` values to the corresponding node options.

The [contributing module](../examples/static-nixos/publish-service.nix) reads `config.registry.central.domain`, contributes the complete `registry.services.metrics` record using the configured Prometheus port, and reads `config.registry.combined.services.metrics.endpoint` into `/etc/metrics-endpoint`. It receives shared data entirely through options.

```sh
nix eval --impure --file examples staticNixos --json
nix eval --impure --file examples staticNixos.validate
```

The endpoint is `monitor.example.test:9191`, combined data contains the complete metrics record, and validation returns `true`. Settings and shared results do not appear in combined data. The example uses the root's committed lock and needs no flake-parts dependency or separate lockfile.

The example function accepts `nixpkgs`, optional `system` (default `x86_64-linux`), and optional `registryFlake` (default the local public exports, accessed without development inputs). It returns the named `nodes`, shared `registry`, and JSON-compatible `result`. The [API reference](api.md#static-nixos-module) documents argument ownership, result paths, reserved names, and setup constraints. The constructor-generated NixOS example above and the generic examples below remain supported.

## Static flake module

This flake-parts consumer imports `flakeModules.default` for project settings and `nixosModules.default` for nodes. Copy the [service schema](../examples/plain-nix/service-schema.nix) to `schema.nix` beside this `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixos-registry.url = "github:petohorvath/nixos-registry";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
    ({ config, ... }:
      let
        shared = config.registry;
        commonModule = {
          imports = [ inputs.nixos-registry.nixosModules.default ];
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.05";
          registry = {
            settings = {
              inherit (shared.settings) schemaModules specialArgs;
            };
            inherit (shared) central combined validate;
          };
        };
      in
      {
        imports = [ inputs.nixos-registry.flakeModules.default ];
        systems = [ "x86_64-linux" ];
        registry.settings = {
          schemaModules = [ ./schema.nix ];
          centralModules = [ { domain = "example.test"; } ];
          nodes = {
            "metrics publisher" = config.flake.nixosConfigurations.monitor;
            "metrics reader" = config.flake.nixosConfigurations.client;
          };
        };
        flake.nixosConfigurations = {
          monitor = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              commonModule
              ({ config, ... }: {
                networking.hostName = "monitor";
                services.prometheus.port = 9191;
                registry.services.metrics = {
                  host = "${config.networking.hostName}.${config.registry.central.domain}";
                  port = config.services.prometheus.port;
                };
              })
            ];
          };
          client = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              commonModule
              ({ config, ... }: {
                environment.etc."metrics-endpoint".text =
                  config.registry.combined.services.metrics.endpoint;
              })
            ];
          };
        };
        flake.lib.registry = { inherit (shared) central combined validate; };
        perSystem = { pkgs, ... }: {
          checks.registry =
            assert shared.validate;
            pkgs.runCommand "registry-validation" { } ''
              touch "$out"
            '';
        };
      });
}
```

Run these commands in the consumer directory after recording its inputs with `nix flake lock`:

```sh
nix eval --no-update-lock-file .#lib.registry.combined --json
nix eval --no-update-lock-file .#lib.registry.validate
nix eval --no-update-lock-file .#nixosConfigurations.client.config.environment.etc.metrics-endpoint.text
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.registry
```

Combined data contains the metrics endpoint `monitor.example.test:9191`, validation returns `true`, and the client's file contains that endpoint. The node names differ from the configuration names; membership is explicit. Both nodes reuse the same project registry and receive shared data through options.

The `registry` check demands `shared.validate`. A port changed to a string, a missing required field, an unknown option, or a conflicting read-only definition causes the check to fail during evaluation. Merely defining the check leaves independent reads lazy: for example, `lib.registry.combined.domain` remains readable with an invalid service port. Use the focused command above for these evaluation-only NixOS nodes. Full `nix flake check --no-update-lock-file` also validates NixOS system outputs and requires machine-specific boot and filesystem settings, which this example omits.

Additional project modules can append schema and central modules and supply distinct node names. Duplicate names at the same priority fail when demanded. The [API reference](api.md#static-flake-module) documents argument ownership and composition. The [consumer tests](../tests/flake-module.nix) exercise this wiring with two contributing NixOS nodes, including a node reading another node's data; they also cover an empty node set and required settings. No NixOS system build or VM boot is needed.

## Plain Nix modules

The [plain Nix example](../examples/plain-nix/default.nix) uses `lib.evalModules` with a [backup-destination schema](../examples/plain-nix/schema.nix). It has two nodes, with no NixOS configuration or hostname requirement.

Each node imports `registry.module`. A node that reads shared data receives `registry` through its `specialArgs`. One contributes its configured port and reads both central and combined data.

```sh
nix eval --impure --file examples plainNix --json
nix eval --impure --file examples plainNix.validate
```

The result includes central and combined data, validation, and the command `backup archive.example.test local.example.test`. The combined archive paths are `[ "/srv/central" "/srv/documents" ]`.

## Flake-parts and separate source repositories

The [flake-parts example](../examples/flake-parts/flake.nix) imports the public `flakeModules.default`, configures `registry.settings`, and constructs two named NixOS nodes from separate source inputs. Its [composition module](../examples/flake-parts/module.nix) owns the [schema](../examples/flake-parts/schema.nix), central definitions, node membership, and common wiring. The source flakes export static NixOS modules:

| Source                                                               | Contribution                                                                       | Shared data it reads                                                                  |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [Service publisher](../examples/sources/service-publisher/nixos.nix) | API port from `services.prometheus.port`, configured as `8443`                     | `config.registry.combined.domain` for its NixOS domain                                |
| [Backup client](../examples/sources/backup-client/nixos.nix)         | Backup hostname and the first `services.openssh.ports` entry, configured as `8022` | `config.registry.central.domain` and `config.registry.combined.services.api.endpoint` |

Central definitions supply `domain = "example.test"` and `services.api.host = "api.example.test"`. The API node supplies only the port, so neither its local record nor the central record is complete. Combined data derives `api.example.test:8443`. The backup node contributes `backup.example.test:8022` and reads the completed API endpoint into `/etc/backup-command`, yielding `backup --api api.example.test:8443`.

The API hostname previously came from the service node; moving it to central definitions demonstrates partial records while preserving both completed endpoints and the backup command. `lib.result.central` selects only the defined central domain and API hostname. Serializing the entire central record would demand its missing port and derived endpoint. `lib.registry` exposes the full project settings and results for selective reads.

The example uses local path inputs for the source flakes. Locked repository URLs can replace those paths without changing the modules. It obtains the public registry exports from its source-only input:

```nix
imports = [ "${inputs.nixos-registry}/flake-module.nix" ];
```

The flake-parts module imports that file and captures `shared = config.registry`. Each node imports this common module before its source module:

```nix
commonModule = {
  imports = [ "${inputs.nixos-registry}/nixos/module.nix" ];
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";
  registry = {
    settings = { inherit (shared.settings) schemaModules specialArgs; };
    inherit (shared) central combined validate;
  };
};
```

The caller uses `inputs.nixpkgs.lib.nixosSystem` to construct each node and assigns the complete evaluations to `registry.settings.nodes`. Both nodes reuse one project-level registry; no constructor call, generated module, or shared-registry module argument is needed on this route. Central modules and node membership stay at project level. Only schema settings and shared results are passed to nodes.

Each local `config.registry.services` contains only that node's service. The API's local port is readable, while its local host and endpoint remain undefined. Shared reads use `config.registry.central` and `config.registry.combined`; explicit validation uses `config.registry.validate` and checks completed combined data. The static interface reserves `settings`, `central`, `combined`, and `validate` at the schema root; `schemaModules` remains a valid schema field. Keep imports and schema structure independent of these configuration results, as described in the [setup rules](api.md#schema-and-central-data-during-node-setup).

Flake-parts' `nixpkgs-lib` input follows the example's `nixpkgs` input. Flake-parts, the registry, and the nodes therefore use the same module-system revision. The registry input uses `flake = false` and imports only its public exports. This keeps the example independent of the registry's development input graph, including when the root suite evaluates the example. The standalone lock preserves the separate node sources and existing dependency selections. Neither source flake depends on the consumer or registry.

The nodes are evaluation examples targeting `x86_64-linux`, exposed under `lib.nodes`. They omit machine-specific boot and filesystem settings and are not exported as deployable `nixosConfigurations`. The flake check validates registry data without demanding a NixOS system build or running a VM. Its check derivations retain both Linux and both best-effort Darwin outputs.

Run the example directly with its own lock file:

```sh
nix eval --no-update-lock-file ./examples/flake-parts#lib.result --json
nix eval --no-update-lock-file ./examples/flake-parts#lib.result.validate
nix flake check --no-update-lock-file ./examples/flake-parts
```

The composition module exposes validation through `perSystem.checks.registry`. The root suite assembles the same public example with its selected `nixpkgs` and the flake-parts source pinned by the example lock. It checks central and combined values, configured NixOS service ports, local contributions, incomplete records, and the dependent backup command under the committed root selection and each policy compatibility override:

```sh
nix eval --impure --file examples flakeParts --json
```

Flake-parts is optional. The [ordinary-flake example](#static-nixos-module) uses the static NixOS module with a shared constructor evaluation, and the [plain Nix examples](#plain-nix-modules) retain generic nodes. The source flakes also retain their `modules.generic.default` exports for constructor-based consumers. Adopting the static interfaces does not require migrating existing constructor users; the [migration notes](../CHANGELOG.md#static-consumer-examples) distinguish their contracts.

## Specific behavior

These examples make merge rules and evaluation behavior visible in their results. Each uses the selected root input. The [API reference](api.md) explains the rules.

| Example                                                                        | Command                                                            | Result to inspect                                                                                           |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| [Partial contributions](../examples/plain-nix/partial-contributions.nix)       | `nix eval --impure --file examples partialContributions --json`    | Completed records from different sources, schema defaults, derived values, and the fields available locally |
| [Override priorities](../examples/plain-nix/priorities.nix)                    | `nix eval --impure --file examples priorities --json`              | A default contribution, a forced contribution, and an override of one port                                  |
| [Conditions and list ordering](../examples/plain-nix/conditional-ordering.nix) | `nix eval --impure --file examples conditionalOrdering --json`     | Enabled contributions around the central paths; central paths alone when disabled                           |
| [Combined reads](../examples/plain-nix/combined-reads.nix)                     | `nix eval --impure --file examples combinedReads --json`           | A contributed host using the shared domain, completed with the central port                                 |
| [Lazy collection](../examples/plain-nix/collection-laziness.nix)               | `nix eval --impure --file examples collectionLaziness.lazy --json` | Domain and endpoint under a `lazyAttrsOf` option, with successful validation                                |

To demand validation separately, use the attribute exposed by the example:

```sh
nix eval --impure --file examples partialContributions.validate
nix eval --impure --file examples priorities.forcedContribution.validate
nix eval --impure --file examples conditionalOrdering.enabled.validate
```

### Examples that intentionally fail

The [scalar-conflict example](../examples/plain-nix/scalar-conflict.nix) sets different archive hosts in a central module and a node. This command fails with an error for `backupDestinations.archive.host`:

```sh
nix eval --impure --file examples scalarConflicts
```

The strict variant of the [collection example](../examples/plain-nix/collection-laziness.nix) and the [value-cycle example](../examples/plain-nix/value-cycle.nix) fail with native recursion errors:

```sh
nix eval --impure --file examples collectionLaziness.strict.combined.settings.domain
nix eval --impure --file examples valueCycles.combined.services.east
```

Both policy compatibility runs check these failures too. They demonstrate limits of the schema or data dependencies and are expected test results.
