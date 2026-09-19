# Agent instructions

## Development and review

Before implementation, read [CONTRIBUTING.md](CONTRIBUTING.md), the [development guide](docs/development.md), and the selected [nixos-project-policy v0.3.0](https://github.com/petohorvath/nixos-project-policy/blob/v0.3.0/POLICY.md). Use the root shell, formatter, and ordinary checks with committed locks; run shared-pin compatibility through the selected policy runner. Preserve plain-import access and the caller-owned module system. Activation of v0.3.0 requires matching central records and verified merge gates; keep validation evidence on the PR and leave activation, merge, and release approval to a human.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `petohorvath/nixos-registry`. Before ticket operations, read `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the five default labels. Before applying triage roles, read `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` and `docs/adr/`. Before exploring the codebase, read `docs/agents/domain.md`.
