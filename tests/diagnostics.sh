#!/usr/bin/env bash
set -euo pipefail

lib_path=$1
registry_path=$2
test_path=$3
system=$4
flake_parts_path=$5
output_dir=$(mktemp -d)
evaluation_store=dummy://
use_static_module=false
trap 'rm -rf "$output_dir"' EXIT

expect_failure() {
  local attribute=$1
  shift

  if nix eval --extra-experimental-features nix-command \
    --impure --json --store "$evaluation_store" \
    --arg lib "import $lib_path" \
    --arg nixpkgs "(import $lib_path/../flake.nix).outputs { self.outPath = $lib_path/..; }" \
    --arg mkRegistry "(import $registry_path/lib).mkRegistry" \
    --arg staticModule "$registry_path/nixos/module.nix" \
    --arg flakeModule "$registry_path/flake-module.nix" \
    --arg flakeParts "(import $flake_parts_path/flake.nix).outputs { self.outPath = $flake_parts_path; nixpkgs-lib.lib = import $lib_path; }" \
    --argstr system "$system" \
    --arg useStaticModule "$use_static_module" \
    --arg serviceSchema "$registry_path/examples/plain-nix/service-schema.nix" \
    --file "$test_path/diagnostics.nix" "$attribute" \
    >"$output_dir/stdout" 2>"$output_dir/stderr"; then
    echo "$attribute: expected evaluation to fail" >&2
    exit 1
  fi
  for fact in "$@"; do
    if ! grep -Fq -- "$fact" "$output_dir/stderr"; then
      echo "$attribute: missing diagnostic fact: $fact" >&2
      cat "$output_dir/stderr" >&2
      exit 1
    fi
  done
}

expect_failure missingOption "missing publication interface" "registry" "import"
expect_failure incompatibleOption "unrelated registry option" "incompatible" "registry.module"
expect_failure unrelatedSubmodule "handwritten contribution root" "incompatible" "registry.module"
expect_failure conflictingInterface "conflicting publication interface" "registry" "conflicting-interface.nix"
check_contribution_diagnostics() {
  expect_failure invalidPort "services.api.port" "node service publisher" "invalid-service.nix"
  expect_failure definitionOrigin "services.api.port" "node generated service publisher" \
    "/generated/service-port.nix"
  expect_failure submoduleOrigin "services.api.port" "node imported service publisher" \
    "invalid-service-record.nix"
  expect_failure moduleOrigin "services.api.port" "node module service publisher" \
    "/modules/service-record.nix"
  expect_failure missingRequired "services.api.port" "no value defined"
  expect_failure unknownOption "services.api.undeclared" "unknown service publisher" "unknown-service.nix"
  expect_failure readOnly "services.api.endpoint" "read-only" "endpoint publisher" "endpoint.nix"
  expect_failure orderedList "backupPaths" "ordered path publisher" "ordered-paths.nix"
  expect_failure priorityConflict "services.api.host" "first address publisher" "second address publisher" \
    "first-address.nix" "second-address.nix"
  expect_failure schemaDeclaration "registry.services.api" "schema-changing publisher" \
    "schema-publication.nix" "schemaModules"
  expect_failure moduleControls "registry" "module-control publisher" "publication-controls.nix" "module controls"
  expect_failure importedSchemaDeclaration "registry.services.api" "importing schema publisher" \
    "shared-schema-data.nix" "schemaModules"
  expect_failure definitionSchemaDeclaration "registry.services.api" "generated schema publisher" \
    "/generated/offending-publication.nix" "schemaModules"
}
check_contribution_diagnostics
expect_failure flakeMissingSchema "registry.settings.schemaModules" "must be set explicitly"
expect_failure flakeMissingNodes "registry.settings.nodes" "must be set explicitly"
expect_failure flakeDuplicateNode "registry.settings.nodes" "duplicate node" \
  "first-project.nix" "second-project.nix"
expect_failure flakeCentralConflict "domain" "first-project.nix" "second-project.nix"
expect_failure flakeDuplicateArgument "registry.settings.specialArgs.schemaLabel" \
  "first-project.nix" "second-project.nix"
# NixOS evaluation creates store files while initializing its package set.
evaluation_store="local?root=$output_dir/store"
use_static_module=true
check_contribution_diagnostics
expect_failure staticInvalidPort.shared "services.api.port" "static service publisher" "invalid-service.nix"
expect_failure staticInvalidPort.local "registry.services.api.port" "invalid-service.nix"
expect_failure flakeStaticInvalidPort "services.api.port" "static service publisher" "invalid-service.nix"
for name in settings central combined validate; do
  expect_failure "staticReservedSchema.$name" "registry.$name" "reserved" \
    "static-schema-collision.nix" "colliding static node"
done

echo "Registry diagnostics retain node identities and source origins."
