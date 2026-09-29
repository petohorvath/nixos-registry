# Contributing

Follow the shared project policy linked from [CI and policy](docs/development.md#ci-and-policy) and the local [development guide](docs/development.md). GitHub enforces the required policy checks on `main`.

## Changes and review

Work on a branch and open a PR with a Conventional Commit title, such as `fix: Preserve contribution source locations`. Describe the resulting behavior, compatibility effects, and validation. Mark breaking changes with `!` and provide migration notes in the [changelog](CHANGELOG.md).

Run root `nix fmt --no-update-lock-file` and `nix flake check --no-update-lock-file`. Run the [policy's local checks](docs/development.md#ci-and-policy), including the stable and unstable test runs that cover the public constructor. Add meaningful tests at public interfaces for behavior changes. Ordinary validation requires no VM execution or virtualization permissions.

A docs-only change edits only Markdown files and leaves their Nix code blocks unchanged; code blocks such as the examples in `docs/examples.md` count as example sources. Locally, a docs-only change needs only the root formatting and flake checks above. When it edits a documented command or that command's documented result, run the command once with its documented setup and record the host and result on the PR. Required hosted checks still apply before merge.

Each PR is squash-merged to one Conventional Commit using its title as the subject. Every merge requires human approval and passing applicable checks; the maintainer may approve and merge without a second reviewer. Agents do not gain merge or bypass authority from successful checks. GitHub requires an up-to-date PR and the [required policy statuses](docs/development.md#ci-and-policy) on `main`, including for administrators. A human may document an urgent exception during a CI infrastructure outage, including the reason, completed checks, and checks owed after recovery; known code or test failures do not qualify.

Keep usage, design, and architectural decisions in repository documentation. Keep implementation history and validation evidence in commits, issues, PRs, and CI rather than separate progress or validation reports.

## Public contract

The public API comprises `lib.mkRegistry` (the only attribute of the root `lib` output); its `lib`, `schemaModules`, `nodes`, `centralModules`, and `specialArgs` arguments and defaults; the generated node `registry` option; and the returned `module`, `central`, `combined`, and `validate` attributes. The [API reference](docs/api.md) defines contribution merging, schema ownership, priorities, ordering, laziness, validation, and diagnostic behavior. Callers own schemas, node construction, and module-system selection.

The static `nixosModules.default` export is also public, including `registry.settings.schemaModules`, `registry.settings.specialArgs`, the `registry.central`, `registry.combined`, and `registry.validate` result options, and direct schema contribution paths. Its [reserved names and wiring](docs/api.md#static-nixos-module) are part of that interface; the generated constructor module retains its existing namespace.

The static `flakeModules.default` export declares project-level `registry.settings.schemaModules`, `nodes`, `centralModules`, and `specialArgs`, and the same three result paths. Its [required settings, defaults, composition, and conflict behavior](docs/api.md#static-flake-module) are public. The enclosing consumer evaluator supplies the module library; callers construct and select nodes and pass shared settings and results through the static NixOS module.

Keep the public exports loadable by path without supplying or evaluating flake inputs: `(import ./lib).mkRegistry`, `nixos/module.nix`, and `flake-module.nix`. The root `nixpkgs` and `flake-parts` inputs can enter normal consumer lock graphs. This path-based contract replaces plain import through the flake's `outputs` function, as [ADR 0002](docs/adr/0002-assemble-the-root-flake-with-flake-parts.md) records, and the original v1 input-free-flake promise, while preserving the library contract.

The `dev` partition supplies the root `checks`, `devShells`, `formatter`, and `tests` development entrypoints. The checks are `evaluation`, `flake-parts`, `formatting`, `lint`, and `workflows`. `tests.<system>` is the nix-unit suite that the `evaluation` check runs. `nix flake check --no-update-lock-file` runs every test and asserts every documented example result using the selected root `nixpkgs`; the project provides no separate example entrypoints. Removing or renaming these entrypoints, check names, or input overrides is a breaking tooling change and requires migration guidance.

## Releases

Release independently using Semantic Versioning tags and [CHANGELOG.md](CHANGELOG.md). Choose a version in a release PR; this development migration does not select an initial version. During 0.x, breaking changes require a minor bump and patch releases remain compatible. Decide readiness for 1.0 explicitly. Released versions and existing tags are immutable.

A release PR specifies its version, changelog, and migration notes. Its human merge authorizes publication only after checks pass on the release commit. Ordinary merges do not publish releases. Preserve existing release history.

## License

Original code uses the [MIT license](LICENSE). Preserve copyright and third-party notices and inherited upstream package license metadata.
