---
status: proposed
---

# Adopt the devnix-labs test standard

Organize the tests as the devnix-labs repositories do: a unit and an integration entry point, each listing its nix-unit suites by hand, and a shared runner that turns each entry point into a check. This replaces the `tests` output and the flake-mode invocation that [ADR 0003](0003-run-the-suite-with-nix-unit.md) chose; nix-unit from the selected `nixpkgs` still runs every case.

## Decisions

- **Two kinds.** Unit suites use only the Nixpkgs `lib` and `mkRegistry`, including `lib.evalModules` on the generated module. Integration suites evaluate NixOS or flake-parts, the hosts whose upstream changes they detect. The `diagnostics` and `recursion` suites split along this line.
- **Source imports.** `tests/test-context.nix` imports the `lib` directory and both static modules by path, as consumers that plainly import the project do. The `flake-outputs` integration suite builds the root outputs from `flake.nix` with the selected inputs and checks that they expose the same code.
- **Entry points as functions of the inputs.** The entry points take `nixpkgs`, `flake-parts`, and `system`, defaulting to the root flake's locked inputs. The runner passes each input as a tree of store paths, so the build sandbox fetches nothing and the policy's `--override-input` runs reach every suite.
- **Checks `unit` and `integration`.** They replace the `evaluation` check. The `flake-parts` check is removed, because the `flake-parts` integration suite already asserts the example's results, and the `workflows` check joins `lint`.

## Consequences

- The flake has no `tests` output, so `nix flake check` no longer warns about an unknown output.
- Suite attribute names are the file names in kebab-case, such as `mk-registry.partial-contributions`.
- The runner starts one nix-unit process per group of cases, which bounds the memory of each process.

## Considered options

- **Keeping the `tests` output with `nix-unit --flake`.** A new input that the check forgets to override fails only inside the sandbox.
