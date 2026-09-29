---
status: proposed
---

# Assemble the root flake with flake-parts

Assemble the root flake with `flake-parts.lib.mkFlake`, following the project family's reference layout in nixos-cross-config. The root declares two inputs, `nixpkgs` and `flake-parts`, whose `nixpkgs-lib` input follows `nixpkgs`. It exports only the system-independent `lib`, `nixosModules.default`, and `flakeModules.default`. A `dev` partition supplies `checks`, `devShells`, and `formatter` for `x86_64-linux` and `aarch64-linux`, reusing the root inputs.

The previous plain `outputs` function assembled a system loop, development outputs, and a `lib` output that mixed the public constructor with the test suite and example results. The flake-parts example added a standalone flake with its own lock, wrapper flakes for its separate sources, and a test helper that fetched flake-parts from that lock and assembled the example by hand. The flake-parts root keeps public exports and development code in separate evaluations, and one root lock pins every root dependency.

## Decisions

- **Path-based plain imports.** `(import ./lib).mkRegistry`, `nixos/module.nix`, and `flake-module.nix` load the public exports from the source tree without evaluating flake inputs. They replace `((import ./flake.nix).outputs { })`, which stops working because `mkFlake` needs the `flake-parts` input.
- **One test command.** The evaluation suite and example results leave `lib`, so `lib` contains only `mkRegistry`. They get no replacement output: `nix flake check --no-update-lock-file` runs every test, its `evaluation` check runs the full suite, and the integration tests assert every example's result.
- **Flake-parts example.** The example becomes a function called by the tests with the root `flake-parts` input and the selected `nixpkgs`. Its lock, wrapper flakes, hand-assembly helper, and separate validation step are removed. The policy runner's `nixpkgs` override therefore controls every root check, including this example.
- **Systems.** The best-effort Darwin outputs are removed; development outputs cover only the two Linux systems that CI requires.

## Consequences

- Flake consumers gain `flake-parts` in their lock graph. Because its library follows `nixpkgs`, they gain no second Nixpkgs input.
- Consumers of `outputs { }` must migrate to the path-based imports, and users of the removed test and example entrypoints under `lib` run `nix flake check` instead, as the [changelog](../../CHANGELOG.md) records.
- `nixosModules.default` and `flakeModules.default` refer to their module files by path rather than holding imported functions, so the module system deduplicates them by file. Consumers that called either output as a function must import the module file instead.
- No example exercises Nix's resolution of a standalone example lock. The root checks evaluate the same example function through the root flake's exports and through the path-based exports.

## Considered options

- **Keep a plain root flake.** This preserves `outputs { }` but retains the hand-written system loop and mixes development values into `lib`.
- **Give the `dev` partition its own inputs flake.** This adds a second lock subject to shared-pin rules without removing any root input: the partition needs only `nixpkgs` and `flake-parts`, which the root already declares.
- **Keep focused evaluation in a development output.** Moving the suite and example results to a per-system development output keeps single-test and single-example commands, but adds entrypoints that the documentation and migration notes must track. One `nix flake check` already runs every test and asserts every example's result.

This decision amends [ADR 0001](0001-separate-test-dependencies-from-root-inputs.md) where it relied on the example lock for the flake-parts revision, on plain-import access through the flake, and on focused test entrypoints. The [development guide](../development.md) defines the resulting commands and test layout.
