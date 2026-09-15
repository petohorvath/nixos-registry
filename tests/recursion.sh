#!/usr/bin/env bash
set -euo pipefail

lib_path=$1
registry_path=$2
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT

expect_recursion() {
  local example=$1
  local attribute=$2

  # Native recursion errors escape builtins.tryEval.
  if nix-instantiate --eval --strict --json --store dummy:// \
    --arg lib "import $lib_path" \
    --arg mkRegistry "((import $registry_path/flake.nix).outputs {}).lib.mkRegistry" \
    --attr "$attribute" "$registry_path/examples/plain-nix/$example.nix" \
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

echo "Schema forcing and value cycles retain native recursion (4 evaluations)."
