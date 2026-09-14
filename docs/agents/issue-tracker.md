# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `petohorvath/nixos-registry`. Operations use the `gh` CLI.

## V1 specification

[Issue #1](https://github.com/petohorvath/nixos-registry/issues/1) tracks the v1 specification and consumer migration. The local specification is `SPEC.md` at the repository root. Ticket planning reads both sources and the issue comments; differences are resolved before drafting tickets.

## Conventions

Commands run from this clone. Outside it, add `--repo petohorvath/nixos-registry`. Multiline bodies are written to a temporary file and passed with `--body-file`.

| Operation | Command |
| --- | --- |
| Create or publish an issue | `gh issue create --title "..." --body-file <path>` |
| Read or fetch a ticket | `gh issue view <number> --json number,title,body,labels,comments` |
| List issues | `gh issue list --state open --json number,title,body,labels,comments` |
| Comment | `gh issue comment <number> --body-file <path>` |
| Apply a label | `gh issue edit <number> --add-label "..."` |
| Remove a label | `gh issue edit <number> --remove-label "..."` |
| Close | `gh issue close <number>` |

Issue listing supports `--label` and `--state` filters. Human-readable ticket output uses `gh issue view <number> --comments`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub issues and pull requests share a number space. Ambiguous references are resolved with `gh pr view <number>`, falling back to `gh issue view <number>`.

## Wayfinding operations

The `wayfinder` skill uses a map issue and child tickets.

- **Map:** an issue labelled `wayfinder:map`, containing Notes, Decisions-so-far, and Fog sections.
- **Child ticket:** a GitHub sub-issue of the map, labelled `wayfinder:<type>`, where the type is `research`, `prototype`, `grilling`, or `task`. If sub-issues are unavailable, the map contains a task list and each child body starts with `Part of #<map>`.
- **Blocking:** native GitHub issue dependencies record blockers. If unavailable, the child body starts with `Blocked by: #<number>, #<number>`. A ticket is unblocked when every blocker is closed.
- **Frontier:** the first open, unassigned child in map order with no open blockers.
- **Claim:** `gh issue edit <number> --add-assignee @me`.
- **Resolve:** post the answer using `gh issue comment <number> --body-file <path>`, close the ticket, and append a finding with its link to the map's Decisions-so-far section.
