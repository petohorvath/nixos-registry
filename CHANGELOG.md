# Changelog

All notable changes to nixos-registry will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-01

### API

- `lib.mkRegistry`, the only attribute of the root `lib` output, takes the required `lib`, `schemaModules`, and `nodes` arguments and the optional `centralModules` (default `[ ]`) and `moduleArgs` (default `{ }`) ([Call `mkRegistry`](docs/api.md#call-mkregistry)).
- `mkRegistry` returns the registry, an attribute set of `schemaModules`, `nodes`, `centralModules`, `moduleArgs`, `module`, `central`, `combined`, and `valid` ([The registry](docs/api.md#the-registry)).
- Each node imports the generated `registry.module`, which imports the static NixOS module and passes the registry to the node as the `registry` module argument ([Nodes](docs/api.md#nodes)).
- Central definitions and node contributions merge under the schema's ordinary module rules, with the [priorities](docs/api.md#override-a-field-or-a-whole-contribution), [list ordering](docs/api.md#conditions-and-list-ordering), and [laziness](docs/api.md#evaluation-and-recursion) that the API reference documents.
- `registry.valid` evaluates all combined data, treating packages and other derivations as leaves that it neither instantiates nor builds. [Validation and diagnostics](docs/api.md#validation-and-diagnostics) shows the pattern that runs it as a flake check.
- `nixosModules.default`, the static NixOS module, declares a node's `registry` contribution root, typed by the schema of the registry in the `registry` module argument. A module from another source can import it to contribute without access to the registry.
- `flakeModules.default`, the static flake module, has module class `flake` and holds one registry at a flake-parts project's `registry` option, with the registry's settings and read-only results ([Static flake module](docs/api.md#static-flake-module)).
- `lib`, `nixos/module.nix`, and `flake-module.nix` load by path without supplying or evaluating flake inputs ([Plain-import access](docs/api.md#plain-import-access)).

### Compatibility

- CI tests the locked `nixos-26.05` Nixpkgs revision and the stable and unstable Nixpkgs pins of nixos-project-policy v0.6 on `x86_64-linux` and `aarch64-linux`.
- A flake consumer locks the root `nixpkgs`, `flake-parts`, `nix-unit`, and `treefmt-nix` inputs. The `nix-unit` and `treefmt-nix` inputs serve only development; leave them out with `inputs.nixos-registry.inputs.nix-unit.follows = "";` and `inputs.nixos-registry.inputs.treefmt-nix.follows = "";`.

### Development

- The `dev` partition supplies the root `checks`, `devShells`, `formatter`, and `tests` outputs. The `nix-unit` check runs the test suites, `treefmt` runs the formatters and linters that `dev/treefmt.nix` enables, and `lint` runs `statix check`.
- `tests.systems.<system>` holds the nix-unit suites as `unit` and `integration`. The [development guide](docs/development.md#run-checks) describes how to run them.

[Unreleased]: https://github.com/petohorvath/nixos-registry/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/petohorvath/nixos-registry/releases/tag/v0.1.0
