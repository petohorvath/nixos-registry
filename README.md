# nixos-registry

nixos-registry is a Nix library that shares typed configuration data between NixOS configurations during evaluation: one configuration contributes a value, such as a service address, and others read the merged result. Projects that evaluate several configurations together use it to define each shared value once, with option types, defaults, and merge rules from the Nix module system.

## Overview

A **schema** declares the shared options. Each **node**, a named and evaluated configuration, contributes definitions beneath its `registry` option, and **central modules** define shared values outside the nodes. The registry merges these definitions into two read-only data sets: **central data** holds the schema defaults and central definitions, and **combined data** adds every node's contribution. [GLOSSARY.md](GLOSSARY.md) defines these terms.

The name refers to this registry of shared data. Nix's [flake registry](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-registry), which maps flake names to locations, is unrelated.

## Requirements

- Nix with the `nix-command` and `flakes` experimental features, for the flake outputs. The library also loads by path without flakes, as [plain-import access](docs/api.md#plain-import-access) describes.
- A Nixpkgs library whose module system matches that of every node. CI tests revisions of the `nixos-26.05` and `nixos-unstable` branches on `x86_64-linux` and `aarch64-linux`.

## Install

Add the flake as an input:

```nix
inputs.nixos-registry = {
  url = "github:petohorvath/nixos-registry";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The flake exports `lib.mkRegistry`, `nixosModules.default`, and `flakeModules.default`. Its `nixpkgs` and `flake-parts` inputs enter the lock graph, but registry evaluation uses the Nixpkgs library that the caller passes in.

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
          specialArgs = { inherit registry; };
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
$ nix eval .#lib.registry.validate
true
```

The `mkRegistry` call takes the schema and the nodes, and returns `registry.module` for each node to import. The server contributes by setting `registry.services.metrics`. The client receives the registry through its own `specialArgs` and reads the merged record from `registry.combined`. The `let` binding allows the registry and the configurations to refer to each other; the schema must stay independent of node data.

These commands evaluate the configurations without building either system. A deployable system also needs its hardware, boot, and filesystem settings.

The [example guide](docs/examples.md) covers plain Nix modules, both static modules, configurations from separate repositories, and specific merge rules, each with its expected result.

## Choose an interface

Each export connects nodes to a registry in a different way:

| Export                 | Wiring                                                                                                      | Nodes read shared data from                              |
| ---------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `lib.mkRegistry`       | Call it once and import the returned `registry.module` in each node, as in [Usage](#usage)                  | A `registry` argument passed through `specialArgs`       |
| `nixosModules.default` | Import it in each NixOS node and pass the schema and one `mkRegistry` result in through its options         | `config.registry.central` and `config.registry.combined` |
| `flakeModules.default` | Import it in a flake-parts project, set `registry.settings`, and import `nixosModules.default` in each node | `config.registry.central` and `config.registry.combined` |

Flake-parts is optional: an ordinary flake can use `nixosModules.default` with its own `mkRegistry` call. With either static module, the caller still constructs each node and lists it explicitly as a member. The static modules reserve `settings`, `central`, `combined`, and `validate` beneath a node's `registry` option, so a schema used with them cannot declare those names.

The [API reference](docs/api.md) documents the arguments, options, and wiring of each export.

## Merging and validation

Central definitions and node contributions follow the schema's ordinary module rules. Lists merge, equal scalar values agree, and conflicting scalar values fail. `lib.mkDefault`, `lib.mkForce`, and `lib.mkOverride` set priorities. Different contributions can supply different fields of one record, which the combined data completes.

Reads are lazy: reading one shared field does not evaluate the others, so an invalid value elsewhere can go unnoticed. `registry.validate` evaluates all combined data, returning `true` or raising an evaluation error. The API reference shows how to [run validation as a flake check](docs/api.md#validation-and-diagnostics).

## Limitations

- Data is shared only during evaluation. Every node must be evaluated in the same Nix evaluation, including configurations whose modules come from separate repositories.
- Schema declarations and the module imports of each node must not depend on node data. A contribution that reads a strict collection, such as `attrsOf`, that it also contributes to, or two values that read each other, causes infinite recursion. The API reference describes the [evaluation rules](docs/api.md#evaluation-and-recursion).
- No version has been released. The [changelog](CHANGELOG.md) records breaking changes and migration steps.

## Contributing

Pull requests are accepted; [CONTRIBUTING.md](CONTRIBUTING.md) describes the review process and the public contract. Report bugs and ask questions in [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues). The [development guide](docs/development.md) covers the development shell, checks, and formatting.

## License

MIT. See [LICENSE](LICENSE).
