# Fixture modules by path: tests import, disable, and deduplicate them by
# path, and diagnostics name their files.
{
  centralIdentity = ./central-identity.nix;
  disabledParent = ./disabled-parent.nix;
  invalidService = ./invalid-service.nix;
  invalidServiceRecord = ./invalid-service-record.nix;
  requiredEndpoint = ./required-endpoint.nix;
  serviceEndpoints = ./service-endpoints.nix;
  sharedSchemaData = ./shared-schema-data.nix;
}
