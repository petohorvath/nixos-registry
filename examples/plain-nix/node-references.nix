# Nodes carry references to their writer tokens to metrics stores on other
# nodes. Each store keeps one copy per reference, keyed by the reference's
# own fields.
{ lib, mkRegistry }:
let
  # A project using nixos-contracts types this field with
  # `contractsLib.types.referenceTo` instead.
  reference = lib.types.submodule {
    options = {
      # Without `_` in either name, joining them with `_` stays unique.
      node = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9-]+";
        description = "Node holding the referenced token.";
      };
      id = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9-]+";
        description = "Name of the token on its node.";
      };
    };
  };

  registry = mkRegistry {
    inherit lib nodes;
    schemaModules = [
      {
        # Reading one store's references evaluates only that store's
        # contributions.
        options.writers = lib.mkOption {
          type = lib.types.lazyAttrsOf (lib.types.listOf reference);
          default = { };
          description = "References to writer tokens, by metrics store.";
        };
      }
    ];
  };

  mkNode =
    name:
    {
      writesTo,
      isStore ? false,
    }:
    lib.evalModules {
      specialArgs = { inherit nodes registry; };
      modules = [
        registry.module
        (
          {
            nodes,
            registry,
            ...
          }:
          let
            references = registry.combined.writers.${name} or [ ];
            copyName = reference: "${reference.node}_${reference.id}";
          in
          {
            options = {
              tokens = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options.value = lib.mkOption {
                      type = lib.types.str;
                      description = "Token value.";
                    };
                  }
                );
                default = { };
                description = "Tokens this node holds, its own and copies.";
              };
              authorizedWriters = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Store configuration naming one copy per line.";
              };
            };
            config = lib.mkMerge [
              {
                tokens.writer.value = "${name} writer token";
                registry.writers = lib.genAttrs writesTo (_: [
                  {
                    node = name;
                    id = "writer";
                  }
                ]);
              }
              (lib.mkIf isStore {
                # A key read through the reference would make this node's
                # token names wait on the sender's, and two stores writing
                # to each other would recurse.
                tokens = lib.listToAttrs (
                  map (
                    reference:
                    lib.nameValuePair (copyName reference) {
                      inherit (nodes.${reference.node}.config.tokens.${reference.id}) value;
                    }
                  ) references
                );
                # The combined order follows merging, so sort what shows it.
                authorizedWriters = lib.concatMapStrings (reference: "${copyName reference}\n") (
                  lib.sortOn copyName references
                );
              })
            ];
          }
        )
      ];
    };

  nodes = lib.mapAttrs mkNode {
    east = {
      writesTo = [ "west" ];
      isStore = true;
    };
    west = {
      writesTo = [ "east" ];
      isStore = true;
    };
    edge.writesTo = [
      "east"
      "west"
    ];
  };
in
{
  inherit (registry) validate;
  tokens = lib.mapAttrs (_: node: lib.mapAttrs (_: token: token.value) node.config.tokens) nodes;
  authorizedWriters = lib.mapAttrs (_: node: node.config.authorizedWriters) {
    inherit (nodes) east west;
  };
}
