---
status: proposed
---

# Format and lint with treefmt-nix

Format and lint the repository as the devnix-labs code quality standard describes: one [treefmt-nix](https://github.com/numtide/treefmt-nix) configuration in `dev/treefmt.nix` supplies the root formatter, the `treefmt` check, and the development shell's tools. The root gains a `treefmt-nix` input for its flake-parts module. Like the `nix-unit` input of [ADR 0004](0004-adopt-the-devnix-labs-test-standard.md), it serves only development, contrary to the separation of development dependencies from root inputs in [ADR 0001](0001-separate-test-dependencies-from-root-inputs.md), and adds no Nixpkgs to consumer lock graphs.

## Decisions

- **One configuration.** `dev/treefmt.nix` enables nixfmt, deadnix, actionlint, and Prettier, with Prettier's settings in the file instead of `.prettierrc.json`. treefmt-nix generates the formatter, the check, and the shell's tools from it, replacing the `registry-fmt` wrapper, `dev/treefmt.toml`, and the hand-written `formatting` check.
- **A `treefmt` check.** It replaces the `formatting` check. It runs every enabled program on the flake source and fails when one would change a file or reports a finding it cannot fix.
- **statix in `lint`.** treefmt-nix would run `statix fix`, which passes lints that it cannot fix, so `lint` runs `statix check` instead. deadnix and actionlint move from `lint` to treefmt.
- **A `treefmt-nix` root input.** Its `nixpkgs` follows the root one, so every program comes from the selected `nixpkgs` and the policy's stable and unstable runs check with those releases' tool versions. nix-unit's own `treefmt-nix` input still follows nothing.
- **No shfmt.** It formatted only `.envrc`.

## Consequences

- Consumer lock graphs gain the treefmt-nix source, but no second Nixpkgs. A consumer can leave it out with `inputs.nixos-registry.inputs.treefmt-nix.follows = "";`.
- `checks.<system>.formatting` becomes `checks.<system>.treefmt`.
- A tool release in the policy's unstable pin can fail the unstable run without a change in this repository. Such a failure is fixed, or the tool configured to keep its old behavior, before the locked `nixpkgs` reaches that release.

## Considered options

- **Keeping the hand-written wrapper and `treefmt.toml`.** It needed a wrapper, a TOML file, and a check that treefmt-nix generates, and it differed from the other devnix-labs repositories.
- **A separate `nixpkgs` input for the tools.** It would keep tool releases out of the stable and unstable runs, at the cost of a second Nixpkgs in consumer lock graphs, which ADR 0001 removed.
