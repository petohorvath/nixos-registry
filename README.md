# nixos-registry

nixos-registry is a Nix library that shares typed configuration data between NixOS configurations during evaluation: one configuration contributes a value, such as a service address, and others read the merged result. Projects that evaluate several configurations together use it to define each shared value once, with option types, defaults, and merge rules from the Nix module system.

## Overview

A **schema** declares the shared options. Each **node**, a named and evaluated configuration, contributes definitions beneath its `registry` option, and **central modules** define shared values outside the nodes. The registry merges these definitions into two read-only data sets: **central data** holds the schema defaults and central definitions, and **combined data** adds every node's contribution. [GLOSSARY.md](GLOSSARY.md) defines these terms.

The name refers to this registry of shared data. Nix's [flake registry](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-registry), which maps flake names to locations, is unrelated.

## Requirements

- Nix with the `nix-command` and `flakes` experimental features, for the flake outputs. The library also loads by path without flakes, as [plain-import access](docs/api.md#plain-import-access) describes.
- A Nixpkgs library whose module system matches that of every node. [CI](docs/development.md#ci-and-policy) tests the locked `nixos-26.05` revision and the shared policy's stable and unstable Nixpkgs pins on `x86_64-linux` and `aarch64-linux`.

## Install

Add the flake as an input:

```nix
inputs.nixos-registry = {
  url = "github:petohorvath/nixos-registry";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The flake exports `lib.mkRegistry`, `nixosModules.default`, and `flakeModules.default`. Its `nixpkgs`, `flake-parts`, and `nix-unit` inputs enter the lock graph but do not select the module system: `mkRegistry` uses the library its caller passes in, and the static modules use the library of their enclosing evaluation.

## Usage

This flake defines two NixOS configurations. `server` contributes the address of its Prometheus service, and `client` reads that address into `/etc/metrics-endpoint`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-registry = {
      url = "github:petohorvath/nixos-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixos-registry, ... }:
    let
      inherit (nixpkgs) lib;

      registry = nixos-registry.lib.mkRegistry {
        inherit lib;
        nodes = nixosConfigurations;
        schemaModules = [
          {
            options.services = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    host = lib.mkOption {
                      type = lib.types.str;
                      description = "Service hostname.";
                    };
                    port = lib.mkOption {
                      type = lib.types.port;
                      description = "Service port.";
                    };
                  };
                }
              );
              default = { };
              description = "Service addresses shared by configurations.";
            };
          }
        ];
      };

      nixosConfigurations = {
        server = lib.nixosSystem {
          modules = [
            registry.module
            (
              { config, ... }:
              {
                nixpkgs.hostPlatform = "x86_64-linux";
                system.stateVersion = "26.05";
                networking.hostName = "server";
                services.prometheus.enable = true;
                registry.services.metrics = {
                  host = "${config.networking.hostName}.example.test";
                  inherit (config.services.prometheus) port;
                };
              }
            )
          ];
        };

        client = lib.nixosSystem {
          modules = [
            registry.module
            (
              { registry, ... }:
              {
                nixpkgs.hostPlatform = "x86_64-linux";
                system.stateVersion = "26.05";
                environment.etc."metrics-endpoint".text =
                  let
                    inherit (registry.combined.services) metrics;
                  in
                  "${metrics.host}:${toString metrics.port}";
              }
            )
          ];
        };
      };
    in
    {
      inherit nixosConfigurations;
      lib.registry = registry;
    };
}
```

Save it as `flake.nix` in an empty directory, then lock its inputs and evaluate the shared data:

```console
$ nix flake lock
$ nix eval .#nixosConfigurations.client.config.environment.etc.metrics-endpoint.text
"server.example.test:9090"
$ nix eval .#lib.registry.combined --json
{"services":{"metrics":{"host":"server.example.test","port":9090}}}
$ nix eval .#lib.registry.valid
true
```

The `mkRegistry` call takes the schema and the nodes, and returns the registry, whose `module` each node imports. The server contributes by setting `registry.services.metrics`. The client reads the merged record from `registry.combined`: `registry.module` passes the registry to every node as the `registry` module argument, while `config.registry` holds the node's own contribution. The `let` binding allows the registry and the configurations to refer to each other; the schema must stay independent of node data.

These commands evaluate the configurations without building either system. A deployable system also needs its hardware, boot, and filesystem settings.

The [example guide](docs/examples.md) covers plain Nix modules, references carried between nodes, NixOS nodes, a flake-parts project with configurations from separate repositories, and specific merge rules, each with its expected result.

## Registry

`mkRegistry` returns the registry as one attribute set:

| Attribute        | Value                                                           |
| ---------------- | --------------------------------------------------------------- |
| `schemaModules`  | The schema modules                                              |
| `nodes`          | The named, evaluated nodes                                      |
| `centralModules` | The central modules                                             |
| `moduleArgs`     | Arguments for the schema and central modules                    |
| `module`         | The generated module, which every node imports                  |
| `central`        | Central data                                                    |
| `combined`       | Combined data                                                   |
| `valid`          | `true` once all combined data evaluates, or an evaluation error |

Each node receives this set as its `registry` module argument. In a flake-parts project, `flakeModules.default` holds the same set at the project's `registry` option, with the first four attributes as its settings. `nixosModules.default` is the static NixOS module, which declares a node's contribution root; `registry.module` imports its implementation, and a module from another source can import it to contribute without access to the registry. Every node receives the whole registry, including `nodes`, but shared data belongs in contributions rather than reads of other nodes' configurations. The [API reference](docs/api.md) documents each export.

## Merging and validation

Central definitions and node contributions merge under the schema's ordinary module rules, so different contributions can [complete one record](docs/api.md#partial-records-defaults-and-derived-values) and [priorities](docs/api.md#override-a-field-or-a-whole-contribution) settle conflicts. Reading one shared field does not evaluate the others; `registry.valid` evaluates all combined data, returning `true` or raising an evaluation error. The API reference shows how to [run validation as a flake check](docs/api.md#validation-and-diagnostics).

## Limitations

- Data is shared only during evaluation. Every node must be evaluated in the same Nix evaluation, including configurations whose modules come from separate repositories.
- Schema declarations and the module imports of each node must not depend on node data. A contribution that reads a collection it also contributes to, when the collection type merges strictly as `attrsOf str` does, or two values that read each other, can cause infinite recursion. The API reference describes the [evaluation rules](docs/api.md#evaluation-and-recursion).
- No version has been released. The [changelog](CHANGELOG.md) records breaking changes and migration steps.

## Contributing

Pull requests are accepted; [CONTRIBUTING.md](CONTRIBUTING.md) describes the review process and the public contract. Report bugs and ask questions in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). The [development guide](docs/development.md) covers the development shell, checks, and formatting.

## License

MIT. See [LICENSE](LICENSE).
