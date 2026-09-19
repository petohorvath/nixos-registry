# nixos-registry

`nixos-registry` is a Nix library for sharing configuration data between NixOS configurations. One configuration can contribute a service address, and another can use that address. Shared data uses option types, defaults, and merge rules from the Nix module system.

The public library entrypoint is `lib.mkRegistry`. The function takes shared option declarations and participating configurations. It returns a module to import, the shared data, and a validation value.

Data is shared during Nix evaluation. All participating configurations must be available in the same Nix evaluation, including configurations defined in separate repositories. Nix's [flake registry](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-registry) is a separate feature for looking up flake names.

## Support

The library is checked against the approved stable and unstable Nixpkgs module systems. Development supports `x86_64-linux` and `aarch64-linux`; existing `x86_64-darwin` and `aarch64-darwin` outputs remain best effort, with no required Darwin CI.

The local workflow and [hosted checks](.github/workflows/check.yml) select [nixos-project-policy v0.3.0](https://github.com/petohorvath/nixos-project-policy/blob/v0.3.0/POLICY.md). PR checks test the committed root input and both shared compatibility revisions on both Linux architectures. Activation of v0.3.0 requires matching central records and verified merge gates; existing v0.1.1 enrollment does not establish enforcement of this upgrade. Report problems through [GitHub Issues](https://github.com/petohorvath/nixos-registry/issues).

## Quickstart

This example assumes familiarity with flakes and NixOS modules. It defines two configurations:

- `server` runs Prometheus and contributes its hostname and configured port.
- `client` reads that service address into an `/etc/metrics-endpoint` file.

A **participant** is a named, evaluated configuration included in the registry. Both configurations are participants. The **schema** declares the shared options; each participant adds data by setting its `registry` option.

Save the following as `flake.nix` in a new directory:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-registry.url = "github:petohorvath/nixos-registry";
  };

  outputs =
    { nixpkgs, nixos-registry, ... }:
    let
      inherit (nixpkgs) lib;

      registry = nixos-registry.lib.mkRegistry {
        inherit lib;
        participants = nixosConfigurations;
        schemaModules = [
          ({ lib, ... }: {
            options.services = lib.mkOption {
              description = "Service addresses shared by configurations.";
              default = { };
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
            };
          })
        ];
      };

      nixosConfigurations = {
        server = lib.nixosSystem {
          modules = [
            registry.module
            ({ config, ... }: {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              networking.hostName = "server";
              services.prometheus.enable = true;
              registry.services.metrics = {
                host = "${config.networking.hostName}.example.test";
                port = config.services.prometheus.port;
              };
            })
          ];
        };

        client = lib.nixosSystem {
          specialArgs = { inherit registry; };
          modules = [
            registry.module
            ({ registry, ... }: {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              environment.etc."metrics-endpoint".text =
                let
                  metrics = registry.combined.services.metrics;
                in
                "${metrics.host}:${toString metrics.port}";
            })
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

Run these commands in that directory with Nix's `nix-command` and `flakes` features enabled. `nix flake lock` records the input revisions in `flake.lock`.

```sh
nix flake lock
nix eval .#nixosConfigurations.client.config.environment.etc.metrics-endpoint.text
# "server.example.test:9090"

nix eval .#lib.registry.combined --json
# {"services":{"metrics":{"host":"server.example.test","port":9090}}}

nix eval .#lib.registry.validate
# true
```

These commands evaluate the configuration without building or starting either system. The example includes the settings needed to evaluate the shared data; deploying a NixOS system also requires its normal hardware and boot configuration.

The example connects four parts:

1. `schemaModules` declares `services` as an attribute set of records with a required `host` and `port`.
2. `participants = nixosConfigurations` includes the evaluated configurations. Each imports the returned `registry.module`.
3. The server sets `registry.services.metrics` to contribute data. Its `config.registry` contains its local contribution.
4. The client receives `registry` through `specialArgs` and reads `registry.combined.services.metrics` to get the shared data.

The `let` block lets the registry and configurations refer to each other. Shared option declarations must stay independent of the participant configurations. The [evaluation rules](docs/api.md#evaluation-and-recursion) explain which shared reads can cause recursion.

## API overview

Call `inputs.nixos-registry.lib.mkRegistry` with an attribute set containing:

| Argument         | Meaning                                                                     | Default                  |
| ---------------- | --------------------------------------------------------------------------- | ------------------------ |
| `lib`            | Nixpkgs library used by the participants                                    | Required                 |
| `schemaModules`  | Modules that declare the shared options                                     | Required                 |
| `participants`   | Attribute set of evaluated configurations, each importing `registry.module` | Required; `{ }` is valid |
| `centralModules` | Modules that define shared values outside the participants                  | `[ ]`                    |
| `specialArgs`    | Arguments for the schema and central modules                                | `{ }`                    |

Use the same Nixpkgs module-system revision for `lib` and every participant. The caller supplies the library used for registry evaluation. Root development inputs may enter consumer lock graphs; [plain-import access](docs/api.md#plain-import-access) keeps the constructor usable without evaluating those inputs.

The function returns an attribute set:

| Attribute           | Use                                                                          |
| ------------------- | ---------------------------------------------------------------------------- |
| `registry.module`   | Import this module in each participant to declare its `registry` option.     |
| `registry.central`  | Read data from the schema and central modules only.                          |
| `registry.combined` | Read data merged from central modules and all participants.                  |
| `registry.validate` | Evaluate all combined data. Returns `true` or raises a Nix evaluation error. |

`config.registry` is local to one participant. `registry.combined` contains the shared data. Pass `registry` to a participant through that configuration's `specialArgs` when its modules need shared reads; the `specialArgs` argument to `mkRegistry` does not do this.

Central definitions and participant contributions use the same merge rules. Lists normally merge; conflicting scalar values fail. Reading one field does not check every other field. Use `registry.validate` to check all combined data.

## Development

After installing the [host prerequisites](docs/development.md#host-prerequisites), run the normal workflow from the repository root:

```sh
nix develop --no-update-lock-file
nix fmt --no-update-lock-file
nix flake check --no-update-lock-file
```

`direnv allow` activates the same shell. The [development guide](docs/development.md) covers focused checks, formatting, and pinned inputs. Normal validation evaluates configurations without building systems or running VMs.

## Contributing

Follow the [contribution guide](CONTRIBUTING.md) for Conventional Commit PR titles, human-approved squash merges, the public contract, and independent releases. Original code uses the [MIT license](LICENSE). The [changelog](CHANGELOG.md) records migration steps.

## Documentation

- [API reference](docs/api.md): arguments, returned attributes, option paths, merging, validation, and recursion.
- [Examples](docs/examples.md): NixOS, plain Nix modules, flake-parts, and specific merge rules, with commands to run them.
- [Development](docs/development.md): tests, formatting, and pinned dependencies.
- [Glossary](CONTEXT.md): project terms.
