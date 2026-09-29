# Development

The [root flake](../flake.nix) delegates the development shell, formatter, and checks to a `dev` flake-parts partition in [dev/](../dev/default.nix). CI runs the shared project policy, and `main` requires its checks before merging, as [CI and policy](#ci-and-policy) describes.

## Host prerequisites

Install Nix with the `nix-command` and `flakes` experimental features enabled, Git for the checkout, and direnv with flake support and shell integration. Flake support may come from direnv itself or nix-direnv. Run `direnv allow` at the repository root after reviewing `.envrc`, or enter the shell directly:

```sh
nix develop --no-update-lock-file
```

The default shell supplies Nix CLI, nil, nixfmt, statix, deadnix, Git, shfmt, Prettier, actionlint, and the root formatter from the selected root `nixpkgs`. These tools require no KVM or other virtualization permissions.

Development outputs and hosted CI support `x86_64-linux` and `aarch64-linux`. Validation evidence must identify the actual host and any untested platforms.

## Run checks

Run commands from the repository root. Reject lock updates during ordinary validation so tests use the committed dependencies:

```sh
nix flake check --no-update-lock-file
```

The suite evaluates the public `lib.mkRegistry` function, generated node module, central data, combined data, and validation using the selected root Nixpkgs module system. Merge tests compare behavior with direct evaluation using the same library. Path-import checks load the `lib` directory and both static modules without the root flake; the library check constructs and uses a registry with a caller-provided library and no flake inputs. Nix checks option types during evaluation; the project has no separate static typechecker.

Test entrypoints mirror source module paths: `lib/mk-registry.nix` maps to `tests/mk-registry.nix`, the other `lib/` helpers have matching files under `tests/`, the `lib/default.nix` entry point maps to `tests/lib.nix`, and the exported `flake-module.nix` and `nixos/module.nix` map to `tests/flake-module.nix` and `tests/nixos/module.nix`. The constructor entrypoint collects smaller case files from `tests/mk-registry/`. Helper behavior is exercised through the public registry interfaces. Cross-module examples and static shared-read cases live in `tests/integration/`; shared fixtures stay in `tests/fixtures/`. `tests/flake.nix` covers the root output shapes declared in `flake.nix`, and `tests/helpers/plain-exports.nix` loads the public exports by path. [tests/evaluation.nix](../tests/evaluation.nix) nests these suites, by source module, into the `tests.<system>` output, and reruns the flake module, NixOS module, and flake-parts example suites with the path-based exports under `pathImported`. [dev/checks.nix](../dev/checks.nix) runs that output with [nix-unit](https://github.com/nix-community/nix-unit) as the `evaluation` check and adds the flake-parts example, formatting, lint, and workflow checks from `tests/default.nix`.

The root checks also cover formatting, statix, deadnix, and workflow validation. Workflow validation checks every `.yml` and `.yaml` file in `.github/workflows` when present; a repository without workflows needs no placeholder. NixOS checks evaluate the affected configuration options for the selected system without building a full system or executing a VM. Normal checks have no VM build dependencies.

`nix flake check --no-update-lock-file` runs all tests. Its `evaluation` check runs every case in the suite, and the integration tests assert the result of every example. To run the suite, or one suite within it, with the locked nix-unit and report each case, pass an attribute path under `tests.<system>`:

```sh
nix run --inputs-from . nixpkgs#nix-unit -- --flake .#tests.x86_64-linux
nix run --inputs-from . nixpkgs#nix-unit -- --flake .#tests.x86_64-linux.diagnostics
```

The alternate-package test selects Prometheus from a separately extended package set while retaining the selected NixOS module system. It verifies package selection and registry behavior without a second Nixpkgs input. Cross-revision package mixing is no longer a separate test commitment; the policy's stable and unstable test runs cover the full suite.

The static flake-module tests use the root `flake-parts` input with the selected root module library. They evaluate both public static imports with real NixOS nodes, composed project settings, explicit membership, empty nodes, and separate schema/central and node arguments. The [separate-source example tests](../tests/integration/flake-parts.nix) call the flake-parts example twice, with the root flake's exports and with the path-based exports, and check its configured NixOS ports, completed partial records, distinct local contributions, and dependent backup command. Its nodes are evaluation-only configurations for the selected system. The diagnostic suite covers missing required settings, duplicate node names and argument keys, and source attribution for central conflicts.

The [static read tests](../tests/integration/static-reads.nix) cover independent central and combined reads, partial records, strict and lazy collections, and explicit validation through consumer flake checks. They demand the check's derivation for valid data and reject unused schema errors, while ordinary reads leave validation unevaluated. The diagnostic suite verifies error attribution through this flake-check path; the recursion suite also covers static collection forcing, value cycles, and node imports selected from their own registry configuration.

The [example guide](examples.md) lists the plain-Nix, NixOS, and flake-parts examples and expected results.

### Failure and diagnostic tests

Failure cases set nix-unit's `expectedError`, which also catches native type errors and infinite recursion that `builtins.tryEval` cannot. The [ordering suite](../tests/ordering-failures.nix) exercises whole-contribution ordering, the [recursion suite](../tests/recursion.nix) demands strict collection reads and cyclic values, and the [diagnostic suite](../tests/diagnostics.nix) asserts option paths, node identities, and available source filenames rather than complete error snapshots. Each diagnostic case matches one regex that lists those facts in message order.

nix-unit matches the error message but not its trace, so library errors name their node and source file in the message itself. A native module-system error, such as a second `registry` option declaration, keeps the node name only in the trace. Tests use `tryEval` only to compare whether reads succeed or fail, as the laziness cases do.

The ordering and contribution diagnostic cases run through both the generated module and actual NixOS nodes importing the static module. The [static contribution suite](../tests/static-interface.nix) compares partial records and definition properties with direct module evaluation, checks the separation of shared wiring from contributions, and reuses the schema-ownership cases through the static public interface.

## Formatting and lint

```sh
nix fmt --no-update-lock-file
nix fmt --no-update-lock-file -- --ci
```

`nix flake check --no-update-lock-file` also runs the `formatting`, `lint`, and `workflows` checks.

[treefmt.toml](../dev/treefmt.toml) covers first-party Nix, shell (including `.envrc`), Markdown, YAML, and JSON. Add any new extensionless shell scripts to its shell includes. Git and direnv state, result links, lockfiles, and generated or vendored trees are excluded. Current fixtures are Nix modules whose exact text is not asserted, so they remain formatted; exclude future exact-text fixtures explicitly. Prettier preserves existing prose wrapping; new prose uses one source line per paragraph.

## Dependencies and policy

The root declares two inputs, `nixpkgs` and `flake-parts`, whose exact revisions are recorded in [flake.lock](../flake.lock). The `flake-parts` library follows `nixpkgs`, and the `dev` partition reuses both inputs without a separate inputs flake. Development tools, formatting, all examples, and all root checks use the selected `nixpkgs`, including the flake-parts example and static flake-module tests. The committed `nixpkgs` revision may differ from the policy's stable and unstable pins. Update it deliberately with `nix flake update nixpkgs`, commit the lock, and rerun ordinary and compatibility checks.

The flake-parts example has no lock of its own. Root checks call it as a function with the root `flake-parts` input and the selected `nixpkgs`, so the policy's `nixpkgs` override also controls it, and `nix flake check --no-update-lock-file` covers it without a separate validation step. Update `flake-parts` deliberately with `nix flake update flake-parts`, commit the lock, and rerun ordinary and compatibility checks.

The public exports still load through a [plain import by path](api.md#plain-import-access), while normal flake consumers acquire the root inputs in their lock graphs. The [changelog](../CHANGELOG.md) documents the removed input overrides and evaluation entrypoints. The shared policy bundles its stable and unstable pins, so the root needs no additional input or compatibility flake. [ADR 0001](adr/0001-separate-test-dependencies-from-root-inputs.md) records this separation and its coverage trade-off; [ADR 0002](adr/0002-assemble-the-root-flake-with-flake-parts.md) records the flake-parts root, the `dev` partition, and path-based plain imports. [ADR 0003](adr/0003-run-the-suite-with-nix-unit.md) records the nix-unit suite, its `pkgs.nix-unit` source, and the `tests` output.

## CI and policy

The [CI workflow](../.github/workflows/check.yml) calls the [shared project policy](https://github.com/petohorvath/nixos-project-policy/blob/v0.5/POLICY.md) in a job named `Policy`. The workflow's `uses:` reference selects the policy release. Apart from the changelog and historical citations in ADRs, that reference and the policy link in this paragraph are the only places that name the policy version; a policy upgrade updates both and adds a changelog entry.

The workflow runs for every opened, synchronized, or reopened PR, for pushes to `main`, and on manual dispatch, with read-only repository permissions. The caller sets no inputs, so the policy runs on its default systems, `x86_64-linux` and `aarch64-linux`. The policy repository is not a flake input, shell dependency, or build dependency.

The policy checks the inputs, public outputs, development shell, and formatter. It also runs root `nix flake check` with the locked `nixpkgs` and with the stable and unstable nixpkgs pins that each policy release bundles, so the repository-owned `formatting`, `lint`, and `workflows` checks run on every system. To run the same checks locally, use the policy's `check .` and `test . --nixpkgs locked|stable|unstable` commands as its [README](https://github.com/petohorvath/nixos-project-policy#local-check) describes. Each local run covers only its host system.

The policy's Caller section lists the statuses to require, and the workflow's `Plan` job writes them to its step summary on every run. GitHub requires an up-to-date PR and these statuses on `main`, including for administrators. Registry has no VM tests, so the policy's VM job is skipped and not required. Passing local checks does not configure GitHub settings or authorize a merge.

### Compatibility checks

The stable and unstable test runs override root `nixpkgs` with `--override-input`, verify the effective input through Nix metadata, and run the full root suite. They use a different effective graph from the committed-lock check, and they fail if the run changes the lock or the sources. The pins stay outside the root lock and consumer dependency graphs, so a pin bump in a policy patch release needs no change here. Nix may reuse cached builds, so a passing run does not mean every check executed again.

## Documentation and issues

Keep the [README](../README.md) focused on the first complete use of the library. Describe arguments and behavior in the [API reference](api.md), and runnable examples in the [example guide](examples.md). Use the terms in [CONTEXT.md](../CONTEXT.md) and follow [CONTRIBUTING.md](../CONTRIBUTING.md) for review and releases.

Issues and specifications live in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). Keep validation evidence on the relevant PR and CI run. Agent-specific issue instructions are in the [issue-tracker guide](agents/issue-tracker.md).
