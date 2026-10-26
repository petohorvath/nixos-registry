# Nodes carry references to their writer tokens to metrics stores on other
# nodes. Each store keeps one copy per reference, keyed by the reference's
# own fields; keys read through the references recurse.
{ lib, mkRegistry }:
let
  # Without `_` in either name, joining them with `_` stays unique.
  nameType = lib.types.strMatching "[a-z0-9-]+";

  # A project using nixos-contracts types this field with
  # `contractsLib.types.referenceTo` instead.
  referenceType = lib.types.submodule {
    options = {
      node = lib.mkOption {
        type = nameType;
        description = "Node holding the referenced token.";
      };
      id = lib.mkOption {
        type = nameType;
        description = "Name of the token on its node.";
      };
    };
  };

  # `toCopyName` names a store's copy of a referenced token, given the
  # reference and the nodes.
  mkExample =
    toCopyName:
    let
      registry = mkRegistry {
        inherit lib nodes;
        schemaModules = [
          {
            # Reading one store's references evaluates only that store's
            # contributions.
            options.writers = lib.mkOption {
              type = lib.types.lazyAttrsOf (lib.types.listOf referenceType);
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
                copies = map (reference: {
                  inherit reference;
                  name = toCopyName { inherit nodes reference; };
                }) (registry.combined.writers.${name} or [ ]);
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
                    tokens = lib.listToAttrs (
                      map (
                        { name, reference }:
                        lib.nameValuePair name {
                          inherit (nodes.${reference.node}.config.tokens.${reference.id}) value;
                        }
                      ) copies
                    );
                    # The combined order follows merging, so sort what shows
                    # it.
                    authorizedWriters = lib.concatMapStrings (copy: "${copy.name}\n") (
                      lib.sortOn (copy: copy.name) copies
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
    };
in
{
  keyedByFields = mkExample ({ reference, ... }: "${reference.node}_${reference.id}");
  /*
    Fails: each store's token names wait on the tokens of the nodes it
    reads, and `east` and `west` read each other, so reading either store's
    tokens recurses. Values read through a reference, as both variants
    read them, do not decide which tokens exist.
  */
  keyedThroughReferences = mkExample (
    { nodes, reference }: nodes.${reference.node}.config.tokens.${reference.id}.value
  );
}
