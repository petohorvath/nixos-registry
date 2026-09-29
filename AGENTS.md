# Agent instructions

## Development and review

Before implementation, read [CONTRIBUTING.md](CONTRIBUTING.md), the [development guide](docs/development.md), and the shared policy linked from [CI and policy](docs/development.md#ci-and-policy). Use the root shell, formatter, and ordinary checks with committed locks; run the policy's local `check` and `test` commands that [CI and policy](docs/development.md#ci-and-policy) names, except for [docs-only changes](CONTRIBUTING.md#changes-and-review). Preserve plain-import access by path to `lib/`, `nixos/module.nix`, and `flake-module.nix` ([ADR 0002](docs/adr/0002-assemble-the-root-flake-with-flake-parts.md)), and the caller-owned module system. Keep validation evidence on the PR and leave required-status changes, merge, and release approval to a human.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `petohorvath/nixos-registry`. Before ticket operations, read `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the five default labels. Before applying triage roles, read `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` and `docs/adr/`. Before exploring the codebase, read `docs/agents/domain.md`.
