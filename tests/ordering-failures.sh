#!/usr/bin/env bash
set -euo pipefail

lib_path=$1
registry_path=$2
test_path=$3
system=$4
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT

# These native type errors escape builtins.tryEval.
for use_static_module in false true; do
  evaluation_store=dummy://
  if [[ $use_static_module == true ]]; then
    evaluation_store="local?root=$output_dir/store"
  fi
  for source in central node; do
    for order in before after explicit; do
      views=(direct combined validate)
      if [[ $source == central ]]; then
        views+=(central)
      fi
      for view in "${views[@]}"; do
        if nix eval --extra-experimental-features nix-command \
          --impure --json --store "$evaluation_store" \
          --arg lib "import $lib_path" \
          --arg mkRegistry "(import $registry_path/lib).mkRegistry" \
          --arg staticModule "$registry_path/nixos/module.nix" \
          --arg nixpkgs "(import $lib_path/../flake.nix).outputs { self.outPath = $lib_path/..; }" \
          --argstr system "$system" --arg useStaticModule "$use_static_module" \
          --argstr source "$source" --argstr order "$order" --argstr view "$view" \
          --file "$test_path/ordering-failures.nix" result >"$output_dir/stdout" 2>"$output_dir/stderr"; then
          echo "$source/$order/$view: expected typed root ordering to fail" >&2
          exit 1
        fi
        if ! grep -Fq "unexpected argument 'priority'" "$output_dir/stderr"; then
          echo "$source/$order/$view: unexpected evaluation failure" >&2
          cat "$output_dir/stderr" >&2
          exit 1
        fi
      done
    done
  done
done

echo "Typed root ordering matches direct failures for generated and static modules (42 evaluations)."
