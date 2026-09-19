# Changelog

## Unreleased

### Breaking tooling migration

Development now runs from the repository root. The separate `dev/` flake is retired.

| Previous interface                       | Replacement                                                    |
| ---------------------------------------- | -------------------------------------------------------------- |
| `nix flake check ./dev`                  | `nix flake check --no-update-lock-file`                        |
| `nix eval ./dev#lib.tests.stable --json` | `nix eval --no-update-lock-file .#lib.tests.stable --json`     |
| `nix eval ./dev#lib.<example>.<channel>` | `nix eval --no-update-lock-file .#lib.<example>.<channel>`     |
| Nix-only formatting from `dev/`          | Root `nix fmt --no-update-lock-file` for all supported sources |
| `nixpkgsStable` input override           | `nixpkgs`                                                      |
| `nixpkgsUnstable` input override         | `nixpkgs-unstable`                                             |

Enter the new default shell with root `nix develop --no-update-lock-file` or `direnv allow`. Update commands and any `--override-input` or `inputs.<name>.follows` references to the new root input names. Approved stable, unstable, and unrelated dependency revisions are preserved.

Root development inputs may now enter consumer lock graphs. This supersedes the original v1 specification's input-free-flake packaging promise. `lib.mkRegistry`, its arguments and defaults, the generated `registry` option, returned attributes, and caller-owned evaluation remain unchanged. Plain-import access through `((import ./flake.nix).outputs { }).lib.mkRegistry` still works without development inputs. Consumers needing a source-only input can set `flake = false`, as the independently locked flake-parts example now does.

### Development

Add root tools, formatting, lint, workflow validation, contribution and release guidance, and an MIT license for original code. Preserve the stable and unstable library, example, diagnostic, and native recursion checks. Retain Darwin development outputs as best effort alongside the two supported Linux architectures.

### Policy adoption

Add the immutable nixos-project-policy v0.1.1 workflow caller for every PR, default-branch push, and manual run. Hosted checks cover both Linux architectures, the effective development shell, formatting and lint, root checks, and PR titles. Local compliance uses the released checker with an explicit trusted current-record checkout.

Enroll the project in current central records. Require PRs and all three policy statuses on `main`, with squash merging and the PR title as its subject. The central drift audit monitors policy selection, pins, and merge controls. Merge and release approval remain human decisions; this migration does not publish a library release.
