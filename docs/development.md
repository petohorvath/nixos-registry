# Development

The [root flake](../flake.nix) supplies the development shell, formatter, and checks under [nixos-project-policy v0.1.1](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/POLICY.md). Adoption remains pending; local checks do not establish hosted readiness or enforced compliance.

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

The policy repository is not a flake input, shell dependency, or build dependency. The shell probe checks the development environment without claiming readiness or adoption. Hosted policy checks and the central version selection are follow-up enrollment work; full readiness checking requires the v0.1.1 checker and an explicit trusted current-record checkout as described in its [checker reference](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/docs/checker.md).

## Documentation and issues

Keep the [README](../README.md) focused on the first complete use of the library. Describe arguments and behavior in the [API reference](api.md), and runnable examples in the [example guide](examples.md). Use the terms in [CONTEXT.md](../CONTEXT.md) and follow [CONTRIBUTING.md](../CONTRIBUTING.md) for review and releases.

Issues and specifications live in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). Keep validation evidence on the relevant PR and CI run. Agent-specific issue instructions are in the [issue-tracker guide](agents/issue-tracker.md).
