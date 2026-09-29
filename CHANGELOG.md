# Changelog

## Unreleased

### Breaking checks: nix-unit suite

Run every test with [nix-unit](https://github.com/nix-community/nix-unit) from the selected root `nixpkgs`. The `evaluation` check now runs the whole suite, including the failure cases that the `diagnostics`, `ordering`, and `recursion` checks ran as separate `nix eval` processes; those three checks are removed. The shell scripts and the hand-written runner are removed, and the root gains no input. [ADR 0003](docs/adr/0003-run-the-suite-with-nix-unit.md) records the decision.

| Removed check                 | Replacement                                                           |
| ----------------------------- | --------------------------------------------------------------------- |
| `checks.<system>.diagnostics` | `checks.<system>.evaluation`, suite `tests.<system>.diagnostics`      |
| `checks.<system>.ordering`    | `checks.<system>.evaluation`, suite `tests.<system>.orderingFailures` |
| `checks.<system>.recursion`   | `checks.<system>.evaluation`, suite `tests.<system>.recursion`        |

The `dev` partition adds a `tests.<system>` output holding the suite, nested by source module. Run it, or one suite in it, with `nix run --inputs-from . nixpkgs#nix-unit -- --flake .#tests.<system>`. `nix flake check` warns that `tests` is an unknown output. It replaces the `lib.tests.<system>` entrypoint that the flake-parts root removed.

Contribution and static reserved-name errors now name their node and source file in the message instead of in an error context. For example, a contribution that declares options previously reported:

```text
… while checking contribution from node `schema-changing publisher' in `/modules/schema-contribution.nix':
error: nixos-registry: contribution at `registry.services.api` declares options; use schemaModules.
```

It now reports:

```text
error: nixos-registry: contribution at `registry.services.api` from node `schema-changing publisher` in `/modules/schema-contribution.nix` declares options; use schemaModules.
```

A static node's schema that uses a reserved name now reports ``nixos-registry: node `colliding static node`: schema option `registry.central` conflicts with a reserved static interface name ...`` instead of the same message under a `while collecting registry data from node ...` context.

Messages for contributions that set `freeformType`, change module controls, or disable schema modules change the same way. A read from a static node's own `registry` option keeps the message without a node. The generated `registry.module` now declares its option in `lib/mk-registry.nix`, so conflicting declarations name that file instead of `<unknown-file>`. The `while collecting registry data from node ...` context remains once per node for native module-system errors.

### Breaking CI statuses: policy v0.5

Call nixos-project-policy `v0.5` through its minor-series tag, with no caller inputs; the policy's default systems are `x86_64-linux` and `aarch64-linux`. The policy checks inputs, public outputs, the development shell, and the formatter, and runs root `nix flake check` with the locked, stable, and unstable nixpkgs revisions. Root checks, dependency locks, and public interfaces are unchanged.

Remove the repository-owned formatting/lint job: `Policy / Tests (locked, <system>)` runs root `nix flake check`, which includes the `formatting`, `lint`, and `workflows` checks. The workflow no longer runs when a PR is only edited, because the policy no longer checks the PR title.

Policy `v0.5` replaces the required statuses rather than renaming them. In the branch protection of `main`, replace `Policy / Verify policy version and load shared pins`, `Policy / Compliance (<system>)`, `Policy / Formatting and lint (<system>)`, `Policy / Project tests (<system>)`, and `Policy / Compatibility (stable|unstable, <system>)` with `Policy / Check (<system>)` and `Policy / Tests (locked|stable|unstable, <system>)` for both Linux systems. The project has no VM tests, so `Policy / VM tests` is skipped and not required. Run the policy locally with `nix run github:petohorvath/nixos-project-policy/v0.5 -- check .`; `--policy-root`, the records checkout, and replay are no longer used. See [CI and policy](docs/development.md#ci-and-policy).

### Breaking flake-parts root

Assemble the root flake with flake-parts. The root declares `nixpkgs` and `flake-parts`, whose `nixpkgs-lib` input follows `nixpkgs`, so flake consumers gain flake-parts in their lock graph but no second Nixpkgs input. The root `lib` contains only `mkRegistry`. A `dev` partition supplies `checks`, `devShells`, and `formatter`, so evaluating `lib`, `nixosModules.default`, or `flakeModules.default` loads no development code. [ADR 0002](docs/adr/0002-assemble-the-root-flake-with-flake-parts.md) records the decision.

The constructor arguments and results, the static NixOS and flake module option interfaces, the check names, and the root Nixpkgs revision are unchanged. The root lock pins flake-parts at the revision the flake-parts example lock used.

Plain import through the flake's `outputs` function no longer works because `mkFlake` needs the `flake-parts` input. Import the public exports by path instead; none of them evaluates flake inputs:

| Previous plain import                                     | Replacement                 |
| --------------------------------------------------------- | --------------------------- |
| `((import ./flake.nix).outputs { }).lib.mkRegistry`       | `(import ./lib).mkRegistry` |
| `((import ./flake.nix).outputs { }).nixosModules.default` | `./nixos/module.nix`        |
| `((import ./flake.nix).outputs { }).flakeModules.default` | `./flake-module.nix`        |
| `modules/nixos.nix`                                       | `nixos/module.nix`          |
| `modules/flake.nix`                                       | `flake-module.nix`          |

With a source-only input declared with `flake = false`, use `(import "${inputs.nixos-registry}/lib").mkRegistry`, `"${inputs.nixos-registry}/nixos/module.nix"`, and `"${inputs.nixos-registry}/flake-module.nix"`.

`nixosModules.default` and `flakeModules.default` now refer to their module files by path instead of holding imported function values. `flakeModules.default` is the path to `flake-module.nix`; `nixosModules.default` is a module that flake-parts marks with `_class = "nixos"` and that imports `nixos/module.nix` by path. The module system therefore identifies and deduplicates each module by its file, including when a configuration imports both the output and the path. Code that called either output as a function must import the module file instead, for example `import "${inputs.nixos-registry}/nixos/module.nix"`.

The test and example entrypoints under `lib` are removed without replacement outputs. Run `nix flake check --no-update-lock-file` instead; the checks below assert what each removed entrypoint exposed:

| Removed entrypoint                 | Covering checks                |
| ---------------------------------- | ------------------------------ |
| `lib.tests.<system>`               | `evaluation`                   |
| `lib.examples`                     | `evaluation`                   |
| `lib.collectionLaziness`           | `evaluation`                   |
| `lib.combinedReads`                | `evaluation`                   |
| `lib.conditionalOrdering`          | `evaluation`                   |
| `lib.partialContributions`         | `evaluation`                   |
| `lib.priorities`                   | `evaluation`                   |
| `lib.scalarConflicts`              | `evaluation`                   |
| `lib.valueCycles`                  | `evaluation`                   |
| `lib.flakePartsExamples`           | `evaluation` and `flake-parts` |
| `lib.nixosExamples.<system>`       | `evaluation`                   |
| `lib.staticNixosExamples.<system>` | `evaluation`                   |

The suite replaces `testPlainImportUsesCallerLibraryWithoutDevelopmentInputs` with `testLibraryDirectoryUsesCallerLibraryWithoutFlakeInputs` and adds cases for root output shapes and path-imported exports.

Remove the best-effort `x86_64-darwin` and `aarch64-darwin` outputs. `checks`, `devShells`, and `formatter` now cover only `x86_64-linux` and `aarch64-linux`. The system-independent `lib`, `nixosModules.default`, and `flakeModules.default` exports remain usable on Darwin hosts.

The flake-parts example is now a function that takes `exports` (the project's `lib`, `nixosModules`, and `flakeModules` exports), `flakeParts`, `nixpkgs`, and optional `system` (default `x86_64-linux`). Its standalone flake, lock, and composition module are removed, as are the wrapper flakes around its separate sources; each source directory keeps its plain `nixos.nix` and generic `module.nix`. Root checks call the example with the root `flake-parts` input and the selected `nixpkgs`, so `nix flake check --no-update-lock-file` replaces its separate validation. The static NixOS example takes a required `exports` argument instead of the optional `registryFlake`.

Development files move into `dev/`: `shell.nix`, `formatter.nix`, and `treefmt.toml`. `dev/checks.nix` loads `tests/default.nix`, which assembles the named checks, and the evaluation suite moves to `tests/evaluation.nix`.

### Policy v0.4.0

Select nixos-project-policy v0.4.0 and declare both required Linux architectures in the member workflow. Keep the existing 11 merge statuses by declaring both formatting/lint checks as additional gates and running them in a member-owned job. Root checks, dependency locks, and public interfaces remain unchanged.

Policy selection and settings now belong to the caller; current policy records hold enrollment identities and approved compatibility pins. Ordinary policy upgrades need no nixos-project-policy change. Local `ci` planning reads the member checkout; use `ci "$PWD" --project nixos-registry` with the selected checker and trusted policy records.

### Breaking contribution terminology

Use **contribution** for node and central option definitions in library code, tests, example modules, and diagnostics, replacing "publication", "publish", and "view". Contribution errors now read `contribution at ...` instead of `publication at ...`, and their error context reads `while checking contribution from node ...` instead of `while checking publication from node ...`; both still report the option path, node, and source file. The NixOS and static NixOS example modules move from `publish-service.nix` to `service-contribution.nix`. Node names such as `metrics publisher` and the flake-parts example's `servicePublisher` input keep their names. The renamed cases below keep their assertions.

| Previous test name                                    | Replacement                                            |
| ----------------------------------------------------- | ------------------------------------------------------ |
| `testCentralViewExcludesNodes`                        | `testCentralDataExcludesNodes`                         |
| `testDisabledNixosServiceDoesNotPublish`              | `testDisabledNixosServiceDoesNotContribute`            |
| `testFilePublicationsRetainModuleSemantics`           | `testFileContributionsRetainModuleSemantics`           |
| `testFreeformPublicationsPreserveModuleMetadata`      | `testFreeformContributionsPreserveModuleMetadata`      |
| `testLegacyPublicationImportsCannotDeclareOptions`    | `testLegacyContributionImportsCannotDeclareOptions`    |
| `testLocallyEnabledOrderedPublicationExample`         | `testLocallyEnabledOrderedContributionExample`         |
| `testNixosNodesReadCombinedDataWhilePublishing`       | `testNixosNodesReadCombinedDataWhileContributing`      |
| `testNixosPublishesConfiguredServicePort`             | `testNixosContributesConfiguredServicePort`            |
| `testNodePublishesFromCombinedDomainExample`          | `testNodeContributesFromCombinedDomainExample`         |
| `testPublicationModuleSyntaxCannotExtendTheSchema`    | `testContributionModuleSyntaxCannotExtendTheSchema`    |
| `testPublicationsCanDisablePublicationModules`        | `testContributionsCanDisableContributionModules`       |
| `testPublicationsCannotDeclareCollectionEntryOptions` | `testContributionsCannotDeclareCollectionEntryOptions` |
| `testPublicationsCannotDisableImportedSchemaModules`  | `testContributionsCannotDisableImportedSchemaModules`  |
| `testPublicationsCannotDisableSchemaModules`          | `testContributionsCannotDisableSchemaModules`          |
| `testPublicationsCannotOpenTheRegistryRoot`           | `testContributionsCannotOpenTheRegistryRoot`           |
| `testRepeatedPublicationImportsRetainModuleIdentity`  | `testRepeatedContributionImportsRetainModuleIdentity`  |
| `testViewsDoNotForceInvalidNodeContributions`         | `testReadsDoNotForceInvalidNodeContributions`          |

### Breaking rename to nodes

Rename participants to **nodes** throughout the public API, examples, diagnostics, and documentation. A node remains a named, evaluated configuration included in a registry; generic `lib.evalModules` configurations remain supported, and node names need not be hostnames.

| Previous interface                           | Replacement                   |
| -------------------------------------------- | ----------------------------- |
| `mkRegistry { participants = ...; }`         | `mkRegistry { nodes = ...; }` |
| `registry.settings.participants`             | `registry.settings.nodes`     |
| Flake-parts example `lib.participants`       | `lib.nodes`                   |
| NixOS example function result `participants` | `nodes`                       |

Rename the argument and option before upgrading; the old names have no compatibility aliases. Keep the same attribute names and whole evaluation results in the node set. Node selection, contribution merging, laziness, and caller-owned module evaluation are unchanged.

Test names replace `Participant` with `Node` and `Participants` with `Nodes`. For example, `testCollectsCentralAndNamedParticipants` becomes `testCollectsCentralAndNamedNodes`. The test-name cleanup table below lists the current replacements. Diagnostic source labels now use `node <name>` instead of `participant <name>`.

### Breaking test-name cleanup

Shorten the longest evaluation test names, as listed below. The suite retains all 145 cases and their assertions.

| Previous test name                                                        | Replacement                                               |
| ------------------------------------------------------------------------- | --------------------------------------------------------- |
| `testCentralContributionHasTheSameRootPrecedenceAsParticipants`           | `testCentralAndNodesShareRootPrecedence`                  |
| `testCentralViewUsesTheSameContributionRootWithoutParticipants`           | `testCentralRootPrioritiesIgnoreNodes`                    |
| `testCollectionTypesDoNotAllowPublicationSchemaDeclarations`              | `testCollectionsRejectContributionSchemaExtensions`       |
| `testLazyCollectionAllowsAContributionToReadAnotherEntryExample`          | `testLazyCollectionExampleReadsSiblingEntries`            |
| `testPublicationsCanDisableModulesRelativeToModulesPath`                  | `testDisablesContributionModulesByRelativePath`           |
| `testPublicationsCannotDisableSchemaModulesNamedByTheirOptionPath`        | `testRejectsDisablingSchemaModulesByOptionPath`           |
| `testPublicationsCannotDisableSchemaModulesRelativeToModulesPath`         | `testRejectsDisablingSchemaModulesByRelativePath`         |
| `testStaticCollectionTypesDoNotAllowContributionSchemaDeclarations`       | `testStaticCollectionsRejectContributionSchemaExtensions` |
| `testStaticConditionsUseLocalConfigurationAndPreserveListOrdering`        | `testStaticLocalConditionsPreserveListOrder`              |
| `testStaticContributionsCanDisableModulesRelativeToModulesPath`           | `testStaticDisablesContributionModulesByRelativePath`     |
| `testStaticContributionsCannotDisableSchemaModulesNamedByTheirOptionPath` | `testStaticRejectsDisablingSchemaModulesByOptionPath`     |
| `testStaticContributionsCannotDisableSchemaModulesRelativeToModulesPath`  | `testStaticRejectsDisablingSchemaModulesByRelativePath`   |
| `testStaticFlakeModuleAcceptsEmptyParticipantsAndDefaultSettings`         | `testStaticFlakeDefaultsAllowEmptyNodes`                  |
| `testStaticModuleImportsAndUnrelatedReadsDoNotDemandSettingsOrValidation` | `testStaticUnrelatedReadsLeaveRegistryUnevaluated`        |
| `testStaticRootOverridesCannotCompleteRecordsFromWeakerContributions`     | `testStaticRootOverridesDiscardWeakerFields`              |
| `testStaticScalarConflictsAndReadOnlyValuesMatchDirectEvaluation`         | `testStaticScalarAndReadOnlyConflictsMatchDirect`         |
| `testStrictCollectionForcesAnUnrelatedThrowLikeDirectEvaluation`          | `testStrictCollectionsForceUnusedEntries`                 |

Test entrypoints now mirror the library and public modules; constructor case files live under `tests/mk-registry/`, and cross-module examples and shared-read tests live under `tests/integration/`.

### Static consumer examples

Use both static public imports in the maintained [separate-source flake-parts example](docs/examples.md#flake-parts-and-separate-source-repositories). Project-level `registry.settings` selects the schema, central definitions, and caller-constructed NixOS nodes. A common module supplies schema settings and the shared `central`, `combined`, and `validate` results; node modules read `config.registry` and contribute at direct schema paths. Its flake check explicitly validates the completed combined data.

The API hostname moves to central definitions and its node contributes the configured Prometheus port. The backup node contributes its configured SSH service and reads the completed API endpoint. Combined endpoints remain `api.example.test:8443` and `backup.example.test:8022`, and the dependent command remains `backup --api api.example.test:8443`. The example's `lib.result.central` now selects the available domain and API hostname; the full central record lacks the port. Its `lib.registry` exposes project settings and results instead of a generated module. Its source flakes add `nixosModules.default` and retain their generic exports.

The static interfaces remain additive apart from the node rename above. Existing constructor consumers, plain-import access, generic nodes, and the ordinary-flake static NixOS example remain supported without flake-parts. Adopting static nodes requires avoiding the schema-root names `settings`, `central`, `combined`, and `validate`, and reading shared results after imports are assembled. These restrictions do not narrow the constructor's schema namespace or its module-argument route for independent setup reads. All committed dependency selections remain unchanged.

### Static flake module

Add `flakeModules.default` for flake-parts consumers to configure one shared registry through `registry.settings` and read `registry.central`, `registry.combined`, and `registry.validate`. Schema modules and nodes must be explicitly supplied; empty collections are valid. Central modules default to `[ ]`, and schema/central arguments default to `{ }`.

Project modules can append schema and central modules and add distinct named nodes. Duplicate node names or argument keys at the same priority fail when demanded instead of recursively merging whole evaluations or arguments. The [usage example](docs/examples.md#static-flake-module) aligns the consumer's module-system revisions and passes shared settings and results through a common static NixOS module. Apart from the node rename above, existing constructor and ordinary-flake consumers need no migration; the core library and static NixOS module remain usable without flake-parts.

### Static NixOS node module

Add `nixosModules.default` for direct imports, `registry.settings` for schema configuration, and `registry.central`, `registry.combined`, and `registry.validate` for caller-supplied shared results. Contributions retain direct schema paths such as `registry.services.metrics.port`. The [ordinary-flake example](docs/examples.md#static-nixos-module) wires nodes to one shared constructor evaluation without flake-parts.

The static interface reserves `settings`, `central`, `combined`, and `validate` at the schema root and rejects collisions. A schema field named `schemaModules` remains valid. Apart from the node rename above, existing constructor consumers need no migration; its generated module, results, plain-import access, and generic nodes remain supported, including schemas using the new static interface's reserved names. When adopting the static module, move schema configuration into `registry.settings`, supply the shared results through the common module, and read them through `config.registry`. Keep constructor-based module arguments for shared reads needed during import discovery.

Preserve partial records, defaults, derived values, conditions, priorities, ordering, and schema ownership through static NixOS nodes. Exclude settings and results inside contribution properties, and prevent definitions containing only shared wiring from suppressing default contributions. Whole-root overrides still select local wiring under ordinary module rules; the [root-property guidance](docs/api.md#properties-at-the-static-contribution-root) shows how to keep it at the selected priority. Explicit empty contributions retain their priority semantics.

### Breaking tooling migration

Development now runs from the repository root with one selected `nixpkgs` input. The separate `dev/` flake is retired. Policy v0.3.0 runs stable and unstable compatibility through exact root-input overrides, replacing the two revisions previously embedded in the root flake.

| Previous interface                                                                                   | Replacement                                                                                     |
| ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `nix flake check ./dev`                                                                              | `nix flake check --no-update-lock-file`                                                         |
| `lib.tests.stable` or `lib.tests.unstable`                                                           | `nix flake check --no-update-lock-file` with the selected root input                            |
| `lib.nixosExamples.<channel>`                                                                        | `nix flake check --no-update-lock-file` with the selected root input                            |
| Other `lib.<example>.<channel>` evaluations                                                          | `nix flake check --no-update-lock-file` with the selected root input                            |
| `checks.<system>.stable` or `.unstable`                                                              | `checks.<system>.evaluation`                                                                    |
| `diagnostics-<channel>`, `ordering-<channel>`, `recursion-<channel>`, `flake-parts-<channel>` checks | `diagnostics`, `ordering`, `recursion`, `flake-parts` under `checks.<system>`                   |
| Nix-only formatting from `dev/`                                                                      | Root `nix fmt --no-update-lock-file` for all supported sources                                  |
| `nixpkgsStable` input override                                                                       | `nixpkgs`                                                                                       |
| `nixpkgsUnstable` or `nixpkgs-unstable` root input override                                          | Override `nixpkgs` for a selected run; use the policy runner for shared-pin compatibility       |
| `flakePartsExampleStable` or `flakePartsExampleUnstable` root input override                         | Removed; the integration uses the example lock's flake-parts source and selected root `nixpkgs` |

Enter the default shell with root `nix develop --no-update-lock-file` or `direnv allow`. Run all tests with `nix flake check --no-update-lock-file`. Update removed input overrides and `inputs.<name>.follows` references to the single root `nixpkgs` input. The root Nixpkgs revision and independently locked example dependencies are unchanged; redundant root lock nodes are removed.

Run both shared compatibility revisions with the [policy runner](docs/development.md#compatibility-checks). The `.stable` and `.unstable` attributes are removed, rather than aliases for the same revision. NixOS checks use the selected system. The alternate-package test now uses a separately extended package set from the selected revision; simultaneous stable/unstable package mixing is no longer a separate coverage commitment.

Root development inputs may now enter consumer lock graphs. This supersedes the original v1 specification's input-free-flake packaging promise. Apart from the node rename above, `lib.mkRegistry`, its argument defaults, the generated `registry` option, returned attributes, and caller-owned evaluation remain unchanged. Plain-import access through `((import ./flake.nix).outputs { }).lib.mkRegistry` still works without development inputs. Consumers needing a source-only input can set `flake = false`, as the independently locked flake-parts example now does.

### Development

Add root tools, formatting, lint, workflow validation, contribution and release guidance, and an MIT license for original code. Preserve the stable and unstable library, example, diagnostic, and native recursion checks. Retain Darwin development outputs as best effort alongside the two supported Linux architectures.

### Policy v0.3.0

Select the immutable nixos-project-policy v0.3.0 caller named `Policy` for every PR, default-branch push, and manual run. Hosted checks separate compliance, formatting/lint, committed-lock project tests, and stable/unstable compatibility on both Linux architectures. The selected checker derives the required status set from policy records. Local compliance and compatibility use an explicit trusted policy records checkout.

Activate v0.3.0 enrollment in current policy records. Require PRs and all 11 policy statuses on `main`, including for administrators, with squash merging and the PR title as its subject. The nixos-project-policy member audit monitors policy selection, pins, and merge controls. Merge and release approval remain human decisions; this migration does not publish a library release.
