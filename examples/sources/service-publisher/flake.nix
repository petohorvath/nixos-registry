# Independent source input; the caller selects the module system and schema.
{
  description = "Example service publication module";

  outputs = _inputs: {
    modules.generic.default = ./module.nix;
  };
}
