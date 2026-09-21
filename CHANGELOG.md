# Changelog

## Unreleased

### Static consumer examples

Use both static public imports in the maintained [separate-source flake-parts example](docs/examples.md#flake-parts-and-separate-source-repositories). Project-level `registry.settings` selects the schema, central definitions, and caller-constructed NixOS participants. A common module supplies schema settings and the shared `central`, `combined`, and `validate` results; participant modules read `config.registry` and contribute at direct schema paths. Its flake check explicitly validates the completed combined data.

The API hostname moves to central definitions and its participant contributes the configured Prometheus port. The backup participant contributes its configured SSH service and reads the completed API endpoint. Combined endpoints remain `api.example.test:8443` and `backup.example.test:8022`, and the dependent command remains `backup --api api.example.test:8443`. The example's `lib.result.central` now selects the available domain and API hostname; the full central record lacks the port. Its `lib.registry` exposes project settings and results instead of a generated module. Its source flakes add `nixosModules.default` and retain their generic exports.

The library interfaces remain additive. Existing constructor consumers, plain-import access, generic participants, and the ordinary-flake static NixOS example remain supported without flake-parts. Adopting static participants requires avoiding the schema-root names `settings`, `central`, `combined`, and `validate`, and reading shared results after imports are assembled. These restrictions do not narrow the constructor's schema namespace or its module-argument route for independent setup reads. All committed dependency selections remain unchanged.

### Static flake module

Add `flakeModules.default` for flake-parts consumers to configure one shared registry through `registry.settings` and read `registry.central`, `registry.combined`, and `registry.validate`. Schema modules and participants must be explicitly supplied; empty collections are valid. Central modules default to `[ ]`, and schema/central arguments default to `{ }`.

Project modules can append schema and central modules and add distinct named participants. Duplicate participant names or argument keys at the same priority fail when demanded instead of recursively merging whole evaluations or arguments. The [usage example](docs/examples.md#static-flake-module) aligns the consumer's module-system revisions and passes shared settings and results through a common static NixOS module. Existing constructor and ordinary-flake consumers need no migration; the core library and static NixOS module remain usable without flake-parts.

### Static NixOS participant module

Add `nixosModules.default` for direct imports, `registry.settings` for schema configuration, and `registry.central`, `registry.combined`, and `registry.validate` for caller-supplied shared results. Contributions retain direct schema paths such as `registry.services.metrics.port`. The [ordinary-flake example](docs/examples.md#static-nixos-module) wires participants to one shared constructor evaluation without flake-parts.

The static interface reserves `settings`, `central`, `combined`, and `validate` at the schema root and rejects collisions. A schema field named `schemaModules` remains valid. Existing constructor consumers need no migration; its arguments, generated module, results, plain-import access, and generic participants remain supported, including schemas using the new static interface's reserved names. When adopting the static module, move schema configuration into `registry.settings`, supply the shared results through the common module, and read them through `config.registry`. Keep constructor-based module arguments for shared reads needed during import discovery.

Preserve partial records, defaults, derived values, conditions, priorities, ordering, and schema ownership through static NixOS participants. Exclude settings and results inside contribution properties, and prevent definitions containing only shared wiring from suppressing default contributions. Whole-root overrides still select local wiring under ordinary module rules; the [root-property guidance](docs/api.md#properties-at-the-static-contribution-root) shows how to keep it at the selected priority. Explicit empty contributions retain their priority semantics.

### Breaking tooling migration

Development now runs from the repository root with one selected `nixpkgs` input. The separate `dev/` flake is retired. Policy v0.3.0 runs stable and unstable compatibility through exact root-input overrides, replacing the two revisions previously embedded in the root flake.

| Previous interface                                                                                   | Replacement                                                                                     |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `nix flake check ./dev`                                                                              | `nix flake check --no-update-lock-file`                                                         |
| `lib.tests.stable` or `lib.tests.unstable`                                                           | `lib.tests.<system>` with the selected root input                                               |
| `lib.nixosExamples.<channel>`                                                                        | `lib.nixosExamples.<system>`                                                                    |
| Other `lib.<example>.<channel>` evaluations                                                          | `lib.<example>` with the selected root input                                                    |
| `checks.<system>.stable` or `.unstable`                                                              | `checks.<system>.evaluation`                                                                    |
| `diagnostics-<channel>`, `ordering-<channel>`, `recursion-<channel>`, `flake-parts-<channel>` checks | `diagnostics`, `ordering`, `recursion`, `flake-parts` under `checks.<system>`                   |
| Nix-only formatting from `dev/`                                                                      | Root `nix fmt --no-update-lock-file` for all supported sources                                  |
| `nixpkgsStable` input override                                                                       | `nixpkgs`                                                                                       |
| `nixpkgsUnstable` or `nixpkgs-unstable` root input override                                          | Override `nixpkgs` for a selected run; use the policy runner for shared-pin compatibility       |
| `flakePartsExampleStable` or `flakePartsExampleUnstable` root input override                         | Removed; the integration uses the example lock's flake-parts source and selected root `nixpkgs` |

Enter the default shell with root `nix develop --no-update-lock-file` or `direnv allow`. For focused evaluation, use `nix eval --no-update-lock-file .#lib.tests.x86_64-linux --json` or `nix eval --no-update-lock-file .#lib.examples --json`. Update removed input overrides and `inputs.<name>.follows` references to the single root `nixpkgs` input. The root Nixpkgs revision and independently locked example dependencies are unchanged; redundant root lock nodes are removed.

Run both shared compatibility revisions with the [policy runner](docs/development.md#compatibility-checks). The `.stable` and `.unstable` attributes are removed, rather than aliases for the same revision. NixOS checks use the selected system. The alternate-package test now uses a separately extended package set from the selected revision; simultaneous stable/unstable package mixing is no longer a separate coverage commitment.

Root development inputs may now enter consumer lock graphs. This supersedes the original v1 specification's input-free-flake packaging promise. `lib.mkRegistry`, its arguments and defaults, the generated `registry` option, returned attributes, and caller-owned evaluation remain unchanged. Plain-import access through `((import ./flake.nix).outputs { }).lib.mkRegistry` still works without development inputs. Consumers needing a source-only input can set `flake = false`, as the independently locked flake-parts example now does.

### Development

Add root tools, formatting, lint, workflow validation, contribution and release guidance, and an MIT license for original code. Preserve the stable and unstable library, example, diagnostic, and native recursion checks. Retain Darwin development outputs as best effort alongside the two supported Linux architectures.

### Policy v0.3.0

Select the immutable nixos-project-policy v0.3.0 caller named `Policy` for every PR, default-branch push, and manual run. Hosted checks separate compliance, formatting/lint, committed-lock project tests, and stable/unstable compatibility on both Linux architectures. The selected checker derives the required status set from central records. Local compliance and compatibility use an explicit trusted current-record checkout.

Activate v0.3.0 enrollment in current central records. Require PRs and all 11 policy statuses on `main`, including for administrators, with squash merging and the PR title as its subject. The central drift audit monitors policy selection, pins, and merge controls. Merge and release approval remain human decisions; this migration does not publish a library release.
