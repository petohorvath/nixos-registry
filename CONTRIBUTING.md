# Contributing

Follow the selected [nixos-project-policy v0.1.1](https://github.com/petohorvath/nixos-project-policy/blob/v0.1.1/POLICY.md) and the local [development guide](docs/development.md).

## Changes and review

Work on a branch and open a PR with a Conventional Commit title, such as `fix: Preserve contribution source locations`. Describe the resulting behavior, compatibility effects, and validation. Mark breaking changes with `!` and provide migration notes in the [changelog](CHANGELOG.md).

Run root `nix fmt --no-update-lock-file` and `nix flake check --no-update-lock-file`. Preserve both stable and unstable public-constructor coverage and independently validate the flake-parts example when its inputs change. Add meaningful tests at public interfaces for behavior changes. Ordinary validation requires no VM execution or virtualization permissions.

Each PR is squash-merged to one Conventional Commit using its title as the subject. Every merge requires human approval and passing applicable checks; the maintainer may approve and merge without a second reviewer. Agents do not gain merge or bypass authority from successful checks. GitHub requires PRs and the [policy status checks](docs/development.md#hosted-checks) on `main`, including for administrators. A human may document an urgent exception during a CI infrastructure outage, including the reason, completed checks, and checks owed after recovery; known code or test failures do not qualify.

Keep usage, design, and architectural decisions in repository documentation. Keep implementation history and validation evidence in commits, issues, PRs, and CI rather than separate progress or validation reports.

## Public contract

The public API comprises `lib.mkRegistry`; its `lib`, `schemaModules`, `participants`, `centralModules`, and `specialArgs` arguments and defaults; the generated participant `registry` option; and the returned `module`, `central`, `combined`, and `validate` attributes. The [API reference](docs/api.md) defines contribution merging, schema ownership, priorities, ordering, laziness, validation, and diagnostic behavior. Callers own schemas, participant construction, and module-system selection.

Keep the constructor usable through `((import ./flake.nix).outputs { }).lib.mkRegistry` without supplying or evaluating development inputs. Root development inputs can enter normal consumer lock graphs. This packaging contract replaces the original v1 input-free-flake promise while preserving the library contract.

Root `devShells`, `formatter`, and `checks` supply development entrypoints. Root `lib.tests` and the documented `lib` example attributes provide focused evaluation. Removing or renaming these entrypoints or input overrides is a breaking tooling change and requires migration guidance.

## Releases

Release independently using Semantic Versioning tags and [CHANGELOG.md](CHANGELOG.md). Choose a version in a release PR; this development migration does not select an initial version. During 0.x, breaking changes require a minor bump and patch releases remain compatible. Decide readiness for 1.0 explicitly. Released versions and existing tags are immutable.

A release PR specifies its version, changelog, and migration notes. Its human merge authorizes publication only after checks pass on the release commit. Ordinary merges do not publish releases. Preserve existing release history.

## License

Original code uses the [MIT license](LICENSE). Preserve copyright and third-party notices and inherited upstream package license metadata.
