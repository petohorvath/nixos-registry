# Independent source input; the caller selects the module system and schema.
{
  description = "Example backup consumer and publication module";

  outputs = _inputs: {
    modules.generic.default = ./module.nix;
  };
}
