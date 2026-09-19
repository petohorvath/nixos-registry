# Development

The [root flake](../flake.nix) supplies the development shell, formatter, and checks under [nixos-project-policy v0.3.0](https://github.com/petohorvath/nixos-project-policy/blob/v0.3.0/POLICY.md). Activation of this version requires matching central records and verified merge gates. Existing v0.1.1 enrollment does not establish v0.3.0 enforcement.

## Host prerequisites

Install Nix with the `nix-command` and `flakes` experimental features enabled, Git for the checkout, and direnv with flake support and shell integration. Flake support may come from direnv itself or nix-direnv. Run `direnv allow` at the repository root after reviewing `.envrc`, or enter the shell directly:

```sh
nix develop --no-update-lock-file
```

The default shell supplies Nix CLI, nil, nixfmt, statix, deadnix, Git, shfmt, Prettier, actionlint, and the root formatter from the selected root `nixpkgs`. These tools require no KVM or other virtualization permissions.

Development supports `x86_64-linux` and `aarch64-linux`. Existing `x86_64-darwin` and `aarch64-darwin` outputs remain available as best effort; they have no required hosted CI. Validation evidence must identify the actual host and any untested platforms.

## Run checks

Run commands from the repository root. Reject lock updates during ordinary validation so tests use the committed dependencies:

```sh
nix flake check --no-update-lock-file
```

The suite evaluates the public `lib.mkRegistry` function, generated participant module, central data, combined data, and validation using the selected root Nixpkgs module system. Merge tests compare behavior with direct evaluation using the same library. A plain-import check constructs and uses a registry with a caller-provided library and no development inputs. Nix checks option types during evaluation; the project has no separate static typechecker.

The root checks also cover formatting, statix, deadnix, and workflow validation. Workflow validation checks every `.yml` and `.yaml` file in `.github/workflows` when present; a repository without workflows needs no placeholder. NixOS checks evaluate the affected configuration options for the selected system without building a full system or executing a VM. Normal checks have no VM build dependencies.

Run the evaluation suite or a focused test, replacing `x86_64-linux` with the required system:

```sh
nix eval --no-update-lock-file .#lib.tests.x86_64-linux --json
nix eval --no-update-lock-file .#lib.tests.x86_64-linux.testCollectsCentralAndNamedParticipants
nix eval --no-update-lock-file .#lib.tests.x86_64-linux.testPlainImportUsesCallerLibraryWithoutDevelopmentInputs
nix eval --no-update-lock-file .#lib.tests.x86_64-linux.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
nix eval --no-update-lock-file .#lib.tests.x86_64-linux.testSeparateSourceParticipantsKeepLocalContributionsDistinct
```

The alternate-package test selects Prometheus from a separately extended package set while retaining the selected NixOS module system. It verifies package selection and registry behavior without a second Nixpkgs input. Cross-revision package mixing is no longer a separate test commitment; the policy runner tests the full suite with each shared revision.

The [example guide](examples.md) lists the plain-Nix, NixOS, and flake-parts examples and expected results. The standalone flake-parts example also uses its own committed lock:

```sh
nix eval --no-update-lock-file ./examples/flake-parts#lib.result --json
nix flake check --no-update-lock-file ./examples/flake-parts
```

### Failure and diagnostic checks

Native ordering and recursion errors require separate evaluator processes because `builtins.tryEval` cannot catch them. [Ordering checks](../tests/ordering-failures.sh) exercise whole-contribution ordering, [recursion checks](../tests/recursion.sh) demand strict collection reads and cyclic values, and [diagnostic checks](../tests/diagnostics.sh) assert option paths, participant identities, and available source filenames rather than complete error snapshots.

Run a focused derivation, replacing `x86_64-linux` with the current system:

```sh
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.diagnostics
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.ordering
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.recursion
```

## Formatting and lint

```sh
nix fmt --no-update-lock-file
nix fmt --no-update-lock-file -- --ci
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.lint
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.workflows
```

[treefmt.toml](../treefmt.toml) covers first-party Nix, shell (including `.envrc`), Markdown, YAML, and JSON. Add any new extensionless shell scripts to its shell includes. Git and direnv state, result links, lockfiles, and generated or vendored trees are excluded. Current fixtures are Nix modules whose exact text is not asserted, so they remain formatted; exclude future exact-text fixtures explicitly. Prettier preserves existing prose wrapping; new prose uses one source line per paragraph.

## Dependencies and policy

The root declares one input, `nixpkgs`, whose exact revision is recorded in [flake.lock](../flake.lock). Development tools, formatting, NixOS examples, and all root checks use that selection. It may differ from the shared compatibility pins. Update it deliberately with `nix flake update nixpkgs`, commit the lock, and rerun ordinary and compatibility checks.

The independent [example lock](../examples/flake-parts/flake.lock) retains its shared stable pin, flake-parts revision, and separate participant sources. Its registry input is source-only, preventing recursive development inputs. [The root integration helper](../tests/flake-parts-example.nix) fetches only the flake-parts source using that lock's exact revision and content hash, instantiates its public outputs with the root's module library, and assembles the example's public outputs. It does not load the example's independent Nixpkgs selection. Validate the standalone flake separately because this assembly does not exercise Nix's resolution of its actual input graph.

The constructor still works through a [plain import](api.md#plain-import-access), while normal flake consumers can acquire the root development input in their lock graphs. The [changelog](../CHANGELOG.md) documents the removed input overrides and renamed evaluation paths. Compatibility pins live in policy records, without an additional root input or compatibility flake. [ADR 0001](adr/0001-separate-test-dependencies-from-root-inputs.md) records this separation and its coverage trade-off.

The immutable v0.3.0 release supplies the policy rules, checker, and workflow. Current [pin records](https://github.com/petohorvath/nixos-project-policy/blob/main/policy/pins.json) and [project records](https://github.com/petohorvath/nixos-project-policy/blob/main/policy/projects.json) supply approved compatibility revisions, required architectures, policy selection, and enrollment state. Independently locked examples still use the approved shared pins. Pin changes follow the shared maintenance procedure and require renewed validation; they do not change the selected policy release.

The policy repository is not a flake input, shell dependency, or build dependency. Run the release's shell probe externally to check effective tools in a cleared inherited environment:

```sh
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.3.0 -- shell "$PWD"
```

### Policy records and readiness

Policy checking requires an explicit trusted checkout of current records. Create it separately, or update an existing clean checkout from policy `main`, and retain its commit with the PR's validation evidence:

```sh
git clone --branch main --single-branch https://github.com/petohorvath/nixos-project-policy.git ../nixos-project-policy-records
git -C ../nixos-project-policy-records rev-parse HEAD
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.3.0 -- \
  --policy-root ../nixos-project-policy-records \
  check "$PWD" --project nixos-registry --readiness --shell
```

The record must select `policyVersion: v0.3.0`. A version mismatch fails even with `--readiness`. During preparation, use a separately identified proposed record checkout for local validation; it is not active policy `main`. With approved pins and `adopted: false`, a successful readiness check reports `ready`. Once activation is recorded, run the same command without `--readiness` and require `pass`. Static checks report compatibility as `not-run`; readiness and shell success do not establish test execution or configure merge gates.

### Compatibility checks

Commit any deliberate root lock changes before compatibility validation: the runner requires the root lock to match its committed copy. Use the same trusted records for both runs:

```sh
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.3.0 -- \
  --policy-root ../nixos-project-policy-records \
  compatibility "$PWD" --project nixos-registry --channel stable
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.3.0 -- \
  --policy-root ../nixos-project-policy-records \
  compatibility "$PWD" --project nixos-registry --channel unstable
```

The runner verifies the effective root input through Nix metadata and executes full root host checks with an exact `--override-input nixpkgs`. It checks that the member source and lock remain unchanged and saves metadata and result artifacts. These runs intentionally use a different effective graph from the committed-lock check; they do not update the member lock. Keep both kinds of evidence on the PR, with the member, checker, and record commits and record digest. Run compatibility on each recorded Linux architecture; cached builds can satisfy checks. See the [checker reference](https://github.com/petohorvath/nixos-project-policy/blob/v0.3.0/docs/checker.md#compatibility-execution-and-evidence) for replay instructions.

### Hosted checks and activation

[Project checks](../.github/workflows/check.yml) calls the immutable v0.3.0 reusable workflow with read-only repository permissions. Its unconditional job is named `Policy` and runs for every opened, synchronized, reopened, or edited PR, including title edits, with no PR branch or path filters. Pushes to `main` and manual dispatch also run the workflow.

The workflow verifies the published immutable release and captures one checker commit and one current-record commit for the run. Job logs identify the exact member revision, normally GitHub's candidate merge commit for a PR. The member's `requiredArchitectures` record retains `x86_64-linux` and `aarch64-linux` for both ordinary and compatibility checks.

After the shared snapshot job, compliance, formatting/lint, project tests, and stable/unstable compatibility run independently on each architecture. Compliance includes the cleared-environment shell probe and applicable Conventional Commit title validation. Project tests use the committed lock; compatibility runs override the selected input. Registry has no VM targets, so the VM result is `not-applicable` and provides no VM-suite evidence.

The selected checker derives required gates from the release, architectures, VM targets, and any `additionalRequiredChecks`. Registry has no additional project gates. Generate the complete list with:

```sh
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.3.0 -- \
  --policy-root ../nixos-project-policy-records ci --project nixos-registry
```

The mandatory statuses are `Policy / Verify policy version and load shared pins`, plus `Policy / Compliance (<architecture>)`, `Policy / Formatting and lint (<architecture>)`, `Policy / Project tests (<architecture>)`, and `Policy / Compatibility (stable, <architecture>)` and `(unstable, <architecture>)` for both Linux architectures. Confirm the actual successful names and workflow implementation before changing merge gates. Retain a complete central `requiredChecks` compatibility list while any member still selects a policy older than v0.3.0.

Coordinate the central selection and member PRs before activation. The hosted workflow reads policy `main`, so a proposed record checkout alone cannot enable member CI. Keep the existing v0.1.1 merge gates until the new statuses are verified and a human authorizes their replacement. Activation requires verified merge controls and audit access, a human-reviewed adoption record, and a passing normal compliance check and hosted drift audit. Keep this evidence on the PRs; local validation does not authorize activation, merges, or release publication.

## Documentation and issues

Keep the [README](../README.md) focused on the first complete use of the library. Describe arguments and behavior in the [API reference](api.md), and runnable examples in the [example guide](examples.md). Use the terms in [CONTEXT.md](../CONTEXT.md) and follow [CONTRIBUTING.md](../CONTRIBUTING.md) for review and releases.

Issues and specifications live in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). Keep validation evidence on the relevant PR and CI run. Agent-specific issue instructions are in the [issue-tracker guide](agents/issue-tracker.md).
