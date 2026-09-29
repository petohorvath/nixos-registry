{
  formatter,
  inputs,
  pkgs,
  system,
}:
import ../tests {
  inherit
    formatter
    inputs
    pkgs
    system
    ;
}
// {
  # Run the nix-unit suite from the `tests` output with the selected inputs.
  evaluation = pkgs.runCommand "registry-evaluation" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
    export HOME=$(realpath .)
    # NixOS evaluation writes to the store, so use a writable chroot store.
    export NIX_REMOTE=$HOME/storedata
    nix-unit --extra-experimental-features flakes \
      --flake ${inputs.self}#tests.${system} \
      --override-input nixpkgs ${inputs.nixpkgs} \
      --override-input flake-parts ${inputs.flake-parts}
    touch "$out"
  '';
}
