# Development

The [root flake](../flake.nix) supplies the development shell, formatter, and checks under [nixos-project-policy v0.1.1](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/POLICY.md). Policy adoption is active, and `main` requires the [hosted policy checks](#hosted-checks) before merging.

## Host prerequisites

Install Nix with the `nix-command` and `flakes` experimental features enabled, Git for the checkout, and direnv with flake support and shell integration. Flake support may come from direnv itself or nix-direnv. Run `direnv allow` at the repository root after reviewing `.envrc`, or enter the shell directly:

```sh
nix develop --no-update-lock-file
```

The default shell supplies Nix CLI, nil, nixfmt, statix, deadnix, Git, shfmt, Prettier, actionlint, and the root formatter from the stable pin. No unstable tool overrides are needed. These tools require no KVM or other virtualization permissions.

Development supports `x86_64-linux` and `aarch64-linux`. Existing `x86_64-darwin` and `aarch64-darwin` outputs remain available as best effort; they have no required hosted CI. Validation evidence must identify the actual host and any untested platforms.

## Run checks

Run commands from the repository root. Reject lock updates during validation so tests use the committed dependencies:

```sh
nix flake check --no-update-lock-file
```

The suite evaluates the public `lib.mkRegistry` function, generated participant module, central data, combined data, and validation using both pinned Nixpkgs module-system revisions. Merge tests compare behavior with direct evaluation using the same library. A plain-import check constructs and uses a registry with a caller-provided library and no development inputs. Nix checks option types during evaluation; the project has no separate static typechecker.

The root checks also cover formatting, statix, deadnix, and workflow validation. Workflow validation checks every `.yml` and `.yaml` file in `.github/workflows` when present; a repository without workflows needs no placeholder. NixOS checks evaluate the affected configuration options without building a full system or executing a VM. Normal checks have no VM build dependencies.

Run one channel or a focused test:

```sh
nix eval --no-update-lock-file .#lib.tests.stable --json
nix eval --no-update-lock-file .#lib.tests.unstable --json
nix eval --no-update-lock-file .#lib.tests.stable.testCollectsCentralAndNamedParticipants
nix eval --no-update-lock-file .#lib.tests.unstable.testPlainImportUsesCallerLibraryWithoutDevelopmentInputs
nix eval --no-update-lock-file .#lib.tests.stable.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
nix eval --no-update-lock-file .#lib.tests.unstable.testSeparateSourceParticipantsKeepLocalContributionsDistinct
```

The [example guide](examples.md) lists the plain-Nix, NixOS, and flake-parts examples and expected results. The standalone flake-parts example also uses its own committed lock:

```sh
nix eval --no-update-lock-file ./examples/flake-parts#lib.result --json
nix flake check --no-update-lock-file ./examples/flake-parts
```

### Failure and diagnostic checks

Native ordering and recursion errors require separate evaluator processes because `builtins.tryEval` cannot catch them. [Ordering checks](../tests/ordering-failures.sh) exercise whole-contribution ordering, [recursion checks](../tests/recursion.sh) demand strict collection reads and cyclic values, and [diagnostic checks](../tests/diagnostics.sh) assert option paths, participant identities, and available source filenames rather than complete error snapshots.

Run a focused derivation, replacing `x86_64-linux` with the current system and `stable` with `unstable` as needed:

```sh
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.diagnostics-stable
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.ordering-stable
nix build --no-update-lock-file --no-link .#checks.x86_64-linux.recursion-stable
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

The root inputs `nixpkgs` and `nixpkgs-unstable` select stable and unstable module systems. [flake.lock](../flake.lock) records their exact revisions and preserves the flake-parts revisions used by both example evaluations. Each flake-parts `nixpkgs-lib` follows its example's selected `nixpkgs`; the example input follows the corresponding root channel.

The independent [example lock](../examples/flake-parts/flake.lock) retains its own stable pin and separate participant sources. Its registry input is source-only, preventing recursive development inputs. The constructor still works through a [plain import](api.md#plain-import-access), while normal flake consumers can acquire root development inputs in their lock graphs. The [changelog](../CHANGELOG.md) documents the retired `dev/` commands and renamed input overrides.

The immutable v0.1.1 release supplies the policy rules and checker. Current [pin records](https://github.com/petohorvath/nixos-project-policy/blob/main/policy/pins.json) and [project records](https://github.com/petohorvath/nixos-project-policy/blob/main/policy/projects.json) on the policy repository's `main` branch supply approved revisions and enrollment state. Pin changes follow the shared maintenance procedure and require renewed validation; they do not change the selected policy release.

Run the release's shell probe externally to check effective tools in a cleared inherited environment:

```sh
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.1.1 -- shell "$PWD"
```

The policy repository is not a flake input, shell dependency, or build dependency. The shell probe validates only the development environment.

### Local compliance

Run the immutable v0.1.1 checker with an explicit trusted checkout of current records. Create the records checkout separately, or update an existing clean checkout from the policy repository's `main` branch, and record its commit with the validation evidence:

```sh
git clone --branch main --single-branch https://github.com/petohorvath/nixos-project-policy.git ../nixos-project-policy-records
git -C ../nixos-project-policy-records rev-parse HEAD
nix run --no-update-lock-file github:petohorvath/nixos-project-policy/v0.1.1 -- \
  --policy-root ../nixos-project-policy-records \
  check "$PWD" --project nixos-registry --shell
```

The expected result is `pass` against the approved pins and active adoption record. See the release's [checker reference](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/docs/checker.md) for report meanings.

### Hosted checks

[Project checks](../.github/workflows/check.yml) calls the immutable v0.1.1 reusable workflow with read-only repository permissions. Its unconditional `policy` job runs for every opened, synchronized, reopened, or edited PR, including title edits, with no PR branch or path filters. Pushes to `main` and manual dispatch also run the workflow.

The workflow verifies that the release is published, immutable, and not a prerelease. It captures the checker commit and one current-record commit for the run, then uses those snapshots in each job. Job logs identify the exact member revision, which is normally GitHub's candidate merge commit for a PR.

Both `x86_64-linux` and `aarch64-linux` jobs run compliance checks with the cleared-environment shell probe, external formatting and Nix lint, root project checks, and applicable Conventional Commit PR-title validation. The reusable workflow's `--readiness` flag preserves the normal checks for an adopted member and reports `pass`. Root checks retain stable and unstable module-system coverage on each architecture. The VM step reports `not-applicable` because the member's VM-target list is empty; it provides no VM-suite evidence.

The required statuses on `main` are:

- `policy / Policy records`
- `policy / Policy (x86_64-linux)`
- `policy / Policy (aarch64-linux)`

These checks are bound to GitHub Actions and must pass on an up-to-date PR before a human squash-merges it. Protection applies to administrators. No VM gate is required. Changes to central records take effect after a human merges the record PR to policy `main`; rerun the member workflow to capture that snapshot.

The central drift audit checks adopted members and their GitHub merge controls using the read-only access described in the [maintenance procedure](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/docs/maintenance.md#audit-access). Keep member, checker, and record revisions and hosted job links on the relevant PRs rather than adding a repository validation report.

## Documentation and issues

Keep the [README](../README.md) focused on the first complete use of the library. Describe arguments and behavior in the [API reference](api.md), and runnable examples in the [example guide](examples.md). Use the terms in [CONTEXT.md](../CONTEXT.md) and follow [CONTRIBUTING.md](../CONTRIBUTING.md) for review and releases.

Issues and specifications live in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). Keep validation evidence on the relevant PR and CI run. Agent-specific issue instructions are in the [issue-tracker guide](agents/issue-tracker.md).
