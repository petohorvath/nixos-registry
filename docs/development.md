# Development

The [development flake](../dev/flake.nix) supplies dependencies, a formatter, and evaluation checks. Keeping these dependencies in `dev/` leaves the public library flake with no required inputs.

Run commands from the repository root with Nix's `nix-command` and `flakes` features enabled, except where a command changes directory explicitly.

## Run checks

Run the complete suite for the current system:

```sh
nix flake check ./dev
```

The suite evaluates the public `lib.mkRegistry` function, generated module, and shared data using both pinned Nixpkgs module-system revisions. Merge tests compare results with direct evaluation using the same library. Nix checks option types during evaluation; the project has no separate static typechecker.

Run the evaluation tests for one revision or one test:

```sh
nix eval ./dev#lib.tests.stable --json
nix eval ./dev#lib.tests.unstable --json
nix eval ./dev#lib.tests.stable.testCollectsCentralAndNamedParticipants
```

The [example guide](examples.md) lists commands for individual examples and their expected results. The complete suite includes successful examples, expected failures, NixOS configuration checks, and the flake-parts validation check on both revisions.

Useful integration checks include:

```sh
nix eval ./dev#lib.tests.stable.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
nix eval ./dev#lib.tests.unstable.testNixosUsesAnotherPackageSetWithTheSelectedModuleSystem
nix eval ./dev#lib.tests.stable.testSeparateSourceParticipantsKeepLocalContributionsDistinct
nix eval ./dev#lib.tests.unstable.testSeparateSourceParticipantsKeepLocalContributionsDistinct
```

NixOS checks evaluate registry data and the affected configuration options. They do not build a full system or boot a VM.

### Failure and diagnostic checks

Some checks run in separate Nix processes because `builtins.tryEval` cannot catch the relevant native errors:

- [Ordering checks](../tests/ordering-failures.sh) cover `mkBefore`, `mkAfter`, and `mkOrder` applied to whole contributions, in both central and participant definitions.
- [Recursion checks](../tests/recursion.sh) cover strict collection evaluation and actual value cycles, during shared reads and validation.
- [Diagnostic checks](../tests/diagnostics.sh) check evaluation failure and facts such as option paths, participant names, and source filenames.

These scripts run against both pinned module-system revisions as part of `nix flake check ./dev`. Diagnostic checks do not match complete error messages.

## Format Nix files

Run the formatter from the development flake directory:

```sh
cd dev
nix fmt -- ../flake.nix flake.nix ../lib/*.nix ../tests/*.nix \
  ../tests/fixtures/*.nix ../examples/*/*.nix \
  ../examples/sources/*/*.nix
```

## Dependencies

The development flake tests the `nixos-26.05` and `nixos-unstable` branches. [dev/flake.lock](../dev/flake.lock) records the exact revisions used for Nixpkgs and flake-parts.

Each flake-parts run uses the selected Nixpkgs input for its `nixpkgs-lib` dependency. The standalone [flake-parts example](../examples/flake-parts/flake.nix) has its own [lock file](../examples/flake-parts/flake.lock). Its local source inputs are versioned in this repository.

## Documentation and issues

Keep the [README](../README.md) focused on the first complete use of the library. Describe arguments and behavior in the [API reference](api.md), and put runnable examples in the [example guide](examples.md). Use the terms in [CONTEXT.md](../CONTEXT.md).

Issues and specifications live in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). Agent-specific issue instructions are in [the issue-tracker guide](agents/issue-tracker.md).
