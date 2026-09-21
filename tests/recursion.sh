#!/usr/bin/env bash
set -euo pipefail

lib_path=$1
registry_path=$2
test_path=$3
system=$4
flake_parts_path=$5
output_dir=$(mktemp -d)
evaluation_store=dummy://
evaluation_dir="$registry_path/examples/plain-nix"
evaluation_args=(
  --arg lib "import $lib_path"
  --arg mkRegistry "((import $registry_path/flake.nix).outputs {}).lib.mkRegistry"
)
trap 'rm -rf "$output_dir"' EXIT

expect_recursion() {
  local example=$1
  local attribute=$2

  # Native recursion errors escape builtins.tryEval.
  if nix eval --extra-experimental-features nix-command \
    --impure --json --store "$evaluation_store" \
    "${evaluation_args[@]}" \
    --file "$evaluation_dir/$example.nix" "$attribute" \
    >"$output_dir/stdout" 2>"$output_dir/stderr"; then
    echo "$example/$attribute: expected native recursion to fail" >&2
    exit 1
  fi
  if ! grep -Fq "infinite recursion encountered" "$output_dir/stderr"; then
    echo "$example/$attribute: unexpected evaluation failure" >&2
    cat "$output_dir/stderr" >&2
    exit 1
  fi
}

expect_recursion collection-laziness strict.combined.settings.domain
expect_recursion collection-laziness strict.validate
expect_recursion value-cycle combined.services.east
expect_recursion value-cycle validate

# NixOS evaluation initializes its package set in a writable store.
evaluation_store="local?root=$output_dir/store"
evaluation_dir=$test_path
evaluation_args=(
  --arg nixpkgs "(import $lib_path/../flake.nix).outputs { self.outPath = $lib_path/..; }"
  --arg flakeParts "(import $flake_parts_path/flake.nix).outputs { self.outPath = $flake_parts_path; nixpkgs-lib.lib = import $lib_path; }"
  --argstr system "$system"
)
expect_recursion static-recursion strict.lib.registry.combined.endpoints.domain
expect_recursion static-recursion strict.lib.registry.validate
expect_recursion static-recursion valueCycle.lib.registry.combined.services.east
expect_recursion static-recursion valueCycle.lib.registry.validate
expect_recursion static-recursion importCycle.lib.registry.validate

echo "Constructor and static shared reads retain native recursion (9 evaluations)."
