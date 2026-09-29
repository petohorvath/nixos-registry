---
status: proposed
---

# Run the suite with nix-unit

Run every test through [nix-unit](https://github.com/nix-community/nix-unit), taken from the selected root `nixpkgs` as `pkgs.nix-unit`, and delete the project's own test runners. The suite becomes a `tests.<system>` output from the `dev` partition, and the `evaluation` check runs nix-unit on it in the build sandbox, overriding `nixpkgs` and `flake-parts` with the selected inputs.

The previous suite needed four runners. A hand-written Nix runner compared `expr` with `expected` and threw on the first mismatch. Three shell scripts started a separate `nix eval` process per failure case, because `builtins.tryEval` cannot catch native type errors, infinite recursion, or error text. nix-unit's `expectedError` catches these in one evaluator, reports every case, and matches the error type and message.

## Decisions

- **Source: `pkgs.nix-unit`.** The package follows the selected `nixpkgs`, so the policy's stable and unstable runs use their matching nix-unit, and the root gains no input.
- **Flake-mode invocation.** The suite needs the real flake `self` for root output tests, so the check runs `nix-unit --flake` against the source with a writable chroot store for NixOS evaluation.
- **A `tests` output.** The suite is a public development output, which also gives single-suite runs. This amends [ADR 0002](0002-assemble-the-root-flake-with-flake-parts.md), which kept tests out of outputs and rejected a focused evaluation output.
- **One `evaluation` check.** It replaces the `evaluation`, `diagnostics`, `ordering`, and `recursion` checks.
- **Self-contained error messages.** nix-unit matches the error message but not its trace. Library errors therefore name the node and source file in the message, replacing error contexts that only repeated them.

## Consequences

- `nix flake check` warns that `tests` is an unknown output. Under the policy, the output must evaluate and cannot be removed after a release without a version bump.
- Contribution and static reserved-name error messages change wording, as the [changelog](../../CHANGELOG.md) records.
- A native module-system error, such as a second `registry` option declaration, still names its node only in the trace, so its diagnostic case cannot assert the node name.

## Considered options

- **nix-unit's flake-parts module.** It requires an `inputs.nix-unit` root input, which enlarges consumer lock graphs.
- **A dev-only inputs flake for nix-unit.** This adds a second lock, which ADR 0002 rejected for the `dev` partition.
- **Matching traces upstream in nix-unit.** The stable nixpkgs pin would lag behind such a change for months.
- **Dropping node and file facts from diagnostic cases.** This removes the coverage the diagnostic suite exists for.
