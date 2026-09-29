---
status: proposed
---

# Separate test dependencies from root inputs

Keep one selected `nixpkgs` input in the root flake for development tools, formatting, ordinary checks, and examples. Under [nixos-project-policy v0.3.0](https://github.com/petohorvath/nixos-project-policy/blob/v0.3.0/POLICY.md), the external policy runner supplies shared stable and unstable revisions through exact root-input overrides. This separates compatibility coverage from the root dependency graph without adding a second Nixpkgs input or a compatibility flake.

The root checks evaluate the flake-parts example with the selected root module library, including during compatibility overrides. [ADR 0002](0002-assemble-the-root-flake-with-flake-parts.md) replaces the original integration helper, which fetched flake-parts using the standalone example lock, with a root `flake-parts` input and an example called as a function.

## Consequences

- Ordinary root checks validate the committed selection. The policy runner verifies the effective override and runs the full root suite for each shared revision on each required Linux architecture, preserving the member source and lock. Compatibility evidence therefore comes from separate runs.
- Remove `flakePartsExampleStable`, `flakePartsExampleUnstable`, and the root `nixpkgs-unstable` input. Focused tests and NixOS examples use a system axis; other examples use the selected input directly. The [changelog](../../CHANGELOG.md) records replacements for the removed overrides, revision-suffixed checks, and `.stable`/`.unstable` evaluation paths.
- The alternate-package test uses a distinct extended package set while retaining the selected module system. Simultaneous stable/unstable package mixing is no longer a separate coverage commitment. Caller-owned registry evaluation and package selection remain supported.
- Root checks retain exact example results and node-contribution assertions. Under ADR 0002, the root lock owns the flake-parts revision, and the example has no lock or separate validation step.
- Keep supported systems explicit in the root flake. Under ADR 0002, development outputs live in a `dev` partition, and plain imports load `lib/`, `nixos/module.nix`, and `flake-module.nix` by path instead of through the flake's `outputs` function. The policy repository stays outside member inputs, imports, shells, and builds.

Keeping two root Nixpkgs inputs would preserve simultaneous cross-revision evaluation but retain the larger consumer dependency graph. Moving those pins into a separate test flake would add another lock solely for compatibility, contrary to the selected policy. The chosen design uses the policy runner for revision selection and, since ADR 0002, the root lock for integration dependencies. The [development guide](../development.md#dependencies-and-policy) defines the resulting commands and validation workflow.
