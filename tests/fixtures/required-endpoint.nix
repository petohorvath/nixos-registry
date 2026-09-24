{ lib, ... }:
{
  options.endpoint = lib.mkOption {
    type = lib.types.str;
    description = ''
      Required service endpoint.
    '';
  };
}
