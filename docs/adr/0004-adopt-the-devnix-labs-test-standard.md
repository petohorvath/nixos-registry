---
status: accepted
---

# Adopt the devnix-labs test standard

Organize the tests as the devnix-labs repositories do: a unit and an integration entry point, each listing its nix-unit suites by hand, run by nix-unit's flake-parts module as one `nix-unit` check. This amends [ADR 0003](0003-run-the-suite-with-nix-unit.md). nix-unit from the selected `nixpkgs` still runs every case, but the module replaces the hand-written `evaluation` check, and the root gains a `nix-unit` input, which ADR 0003 rejected. The input serves only the tests, contrary to the separation of test dependencies from root inputs in [ADR 0001](0001-separate-test-dependencies-from-root-inputs.md); unlike the second Nixpkgs that ADR 0001 removed, it adds no Nixpkgs to consumer lock graphs.

## Decisions

- **Two kinds.** Unit suites use only the Nixpkgs `lib` and `mkRegistry`, including `lib.evalModules` on the generated module. Integration suites evaluate NixOS or flake-parts, the hosts whose upstream changes they detect. The `diagnostics` and `recursion` suites split along this line.
- **Source imports.** `tests/test-context.nix` imports the `lib` directory and both static modules by path, as consumers that plainly import the project do. The `flake-outputs` integration suite checks that the flake's outputs expose the same code.
- **nix-unit's flake-parts module.** The entry points take `nixpkgs`, `flake-parts`, `self`, and `system` without defaults. `dev/default.nix` passes the flake's inputs and sets the module's `inputs` to every root input, so the policy's `--override-input` runs reach every suite and a new input cannot be left out. The module's `tests.systems.<system>` output holds the suites under `unit` and `integration`, with the module's system-agnostic tests turned off, and its `nix-unit` check replaces `evaluation`. Only the integration entry point takes `system`, because only its suites evaluate NixOS.
- **A `nix-unit` root input.** Its `nixpkgs` input follows the root one, and its `treefmt-nix` and `nix-github-actions` inputs follow nothing, so consumers lock only the nix-unit source. The check takes the nix-unit program from `nixpkgs`, as ADR 0003 chose.
- **Fewer checks.** The `flake-parts` check is removed, because the `flake-parts-example` integration suite asserts the example's results and evaluates its check's derivation, and the `workflows` check joins `lint`.

## Consequences

- Consumer lock graphs gain the nix-unit source, but no second Nixpkgs. A consumer can leave it out with `inputs.nixos-registry.inputs.nix-unit.follows = "";`.
- The `tests` output moves from `tests.<system>` to `tests.systems.<system>`, and suite attribute names are now the file names in kebab-case, such as `unit.mk-registry.partial-contributions`.
- One nix-unit process evaluates every suite. The check first copies each input, including the Nixpkgs source, into a store in its build directory.

## Considered options

- **A custom runner per repository**, which rebuilt the inputs from store paths and ran each group of cases in its own process. It avoided the copies and bounded memory per group, but it was about 200 lines of shared code to keep identical across repositories.
- **Keeping the hand-written `evaluation` check.** It overrides only the inputs it names, so a new input that it leaves out fails only inside the sandbox.
