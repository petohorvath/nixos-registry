{ lib, ... }:
{
  registry = lib.mkMerge [
    { services.api.host = "api.example.test"; }
    { services.api.port = lib.mkForce "invalid port"; }
  ];
}
