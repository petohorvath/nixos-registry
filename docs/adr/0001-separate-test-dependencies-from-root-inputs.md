---
status: proposed
---

# Separate test dependencies from root inputs

Keep one selected `nixpkgs` input, plus flake-parts with `nixpkgs-lib` following that selection, in the root flake for development tools, formatting, ordinary checks, and examples. Under [nixos-project-policy v0.4.0](https://github.com/petohorvath/nixos-project-policy/blob/v0.4.0/POLICY.md), the external policy runner supplies shared stable and unstable revisions through exact root-input overrides. This separates compatibility coverage from the root dependency graph without adding a second Nixpkgs input or a compatibility flake.

The [integration helper](../../examples/flake-parts/evaluate.nix) fetches the flake-parts source using the exact revision and content hash in the existing [standalone example lock](../../examples/flake-parts/flake.lock). It assembles the example's public outputs and separate node sources with the selected root module library, including during compatibility overrides. It does not load the example's independent Nixpkgs selection or implement recursive flake-input resolution.

## Consequences

- Ordinary root checks validate the committed selection. The policy runner verifies the effective override and runs the full root suite for each shared revision on each required Linux architecture, preserving the member source and lock. Compatibility evidence therefore comes from separate runs.
- Remove `flakePartsExampleStable`, `flakePartsExampleUnstable`, and the root `nixpkgs-unstable` input. Focused tests and NixOS examples use a system axis; other examples use the selected input directly. The [changelog](../../CHANGELOG.md) records replacements for the removed overrides, revision-suffixed checks, and `.stable`/`.unstable` evaluation paths.
- The alternate-package test uses a distinct extended package set while retaining the selected module system. Simultaneous stable/unstable package mixing is no longer a separate coverage commitment. Caller-owned registry evaluation and package selection remain supported.
- Root checks retain exact example results and node-contribution assertions. The standalone example still requires independent validation because local assembly does not exercise Nix's resolution of its actual inputs. Its Nixpkgs selection remains subject to shared-pin rules; its lock owns the flake-parts revision used by both evaluations.
- Keep development outputs and supported systems explicit in the root flake. Use a flake-parts development partition for shell, formatter, and checks. Keep `lib` limited to `mkRegistry`; direct import of `lib/default.nix` needs no development inputs. Tests and examples use file entrypoints rather than library exports. The policy repository stays outside member inputs, imports, shells, and builds.

Keeping two root Nixpkgs inputs would preserve simultaneous cross-revision evaluation but retain the larger consumer dependency graph. Moving those pins into a separate test flake would add another lock solely for compatibility, contrary to the selected policy. The chosen design uses the policy runner for revision selection and the existing example lock for integration dependencies. The [development guide](../development.md#dependencies-and-policy) defines the resulting commands and validation workflow.
