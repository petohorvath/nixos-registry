{
  writeShellApplication,
  treefmt,
  nixfmt,
  shfmt,
  prettier,
}:
writeShellApplication {
  name = "registry-fmt";
  runtimeInputs = [
    treefmt
    nixfmt
    shfmt
    prettier
  ];
  text = ''
    exec treefmt --tree-root . --walk filesystem \
      --config-file ${../treefmt.toml} "$@"
  '';
}
