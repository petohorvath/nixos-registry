# test-standard v1: copied from the test-standard skill; do not edit here.
/*
  Turn a nix-unit entry point into a check. The entry point's arguments
  come from the flake's inputs, rebuilt from store paths, so the sandbox
  fetches nothing and input overrides reach every suite. Each group, an
  attrset that directly holds `test*` attributes, runs in its own nix-unit
  process.
*/
{
  inputs,
  pkgs,
  repo,
  srcDir,
}:
{
  kind,
  name ? kind,
  suites ? null,
  extraArgs ? { },
  requiredSystemFeatures ? [ ],
  postCheck ? "",
  jobs ? null,
}:
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;

  entryPoint = "${srcDir}/tests/${kind}";
  evaluationInputs = "${srcDir}/tests/helpers/evaluation-inputs.nix";

  # A flake input as a tree of store paths, keeping every transitive input.
  toTree =
    input:
    if input._type or null == "flake" then
      {
        path = input.outPath;
        inputs = lib.mapAttrs (_: toTree) input.inputs;
      }
    else
      {
        path = input.outPath;
        flake = false;
      };

  # Interpolating the store paths makes them inputs of the derivation.
  renderTree =
    tree:
    if tree ? flake then
      ''{ path = "${tree.path}"; flake = false; }''
    else
      let
        renderedInputs = lib.mapAttrsToList (
          inputName: input: "${lib.strings.escapeNixIdentifier inputName} = ${renderTree input};"
        ) tree.inputs;
      in
      ''{ path = "${tree.path}"; inputs = { ${toString renderedInputs} }; }'';

  declaredArgs = builtins.functionArgs (import entryPoint);
  inputArgs = lib.filterAttrs (
    argName: _: inputs ? ${argName} && !(extraArgs ? ${argName})
  ) declaredArgs;
  argFlags = lib.concatLists (
    lib.mapAttrsToList (argName: _: [
      "--arg"
      argName
      "(import ${evaluationInputs}) ${renderTree (toTree inputs.${argName})}"
    ]) inputArgs
    ++ lib.mapAttrsToList (argName: expression: [
      "--arg"
      argName
      expression
    ]) extraArgs
    ++ [
      [
        "--argstr"
        "system"
        system
      ]
    ]
  );

  # Lists the attribute paths of the groups in the selected suites.
  findGroups = pkgs.writeText "${repo}-${name}-groups.nix" ''
    { ... }@args:
    let
      suites = import ${entryPoint} args;
      selected = ${
        if suites == null then
          "builtins.attrNames suites"
        else
          "[ ${toString (map builtins.toJSON suites)} ]"
      };
      isTest = name: builtins.substring 0 4 name == "test";
      findGroups =
        path: set:
        let
          names = builtins.attrNames set;
          isNested = name: !isTest name && builtins.isAttrs set.''${name};
          findNested = name: findGroups (path ++ [ name ]) set.''${name};
        in
        (if builtins.any isTest names then [ path ] else [ ])
        ++ builtins.concatMap findNested (builtins.filter isNested names);
    in
    {
      groups = builtins.concatMap (
        name: findGroups [ name ] suites.''${name}
      ) selected;
    }
  '';

  # Selects one group's tests, leaving out its nested groups, under the
  # group's attribute path.
  selectGroup = pkgs.writeText "${repo}-${name}-group.nix" ''
    { groupPath, ... }@args:
    let
      entryArgs = builtins.removeAttrs args [ "groupPath" ];
      path = builtins.fromJSON groupPath;
      depth = builtins.length path;
      group = builtins.foldl' (set: name: set.''${name}) (
        import ${entryPoint} entryArgs
      ) path;
      isTest = name: builtins.substring 0 4 name == "test";
      tests = builtins.removeAttrs group (
        builtins.filter (name: !isTest name) (builtins.attrNames group)
      );
      nameAt = index: builtins.elemAt path (depth - 1 - index);
    in
    builtins.foldl' (inner: index: { ''${nameAt index} = inner; }) tests (
      builtins.genList (index: index) depth
    )
  '';

  # nix-unit releases before 2.35 need a directory for their GC roots.
  needsGcRootsDir = lib.versionOlder pkgs.nix-unit.version "2.35";
  gcRootsFlag = ''--gc-roots-dir "$TMPDIR/gc-roots-$index"'';
in
pkgs.runCommand "${repo}-${name}"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.nix
      pkgs.nix-unit
    ];
    inherit requiredSystemFeatures;
  }
  ''
    export HOME="$TMPDIR"
    evalStore="$TMPDIR/eval-store"
    argFlags=(${lib.escapeShellArgs argFlags})

    nix --extra-experimental-features nix-command eval \
      --eval-store "$evalStore" --show-trace --json \
      --file ${findGroups} "''${argFlags[@]}" groups >"$TMPDIR/groups.json"
    mapfile -t groups < <(jq -c '.[]' "$TMPDIR/groups.json")
    if (( ''${#groups[@]} == 0 )); then
      echo "${repo}-${name}: no test groups found" >&2
      exit 1
    fi

    runGroup() {
      local index=$1 group=$2
      if nix-unit --eval-store "$evalStore" --show-trace \
        ${lib.optionalString needsGcRootsDir gcRootsFlag} \
        "''${argFlags[@]}" --argstr groupPath "$group" ${selectGroup} \
        >"$TMPDIR/group-$index.log" 2>&1; then
        echo 0 >"$TMPDIR/group-$index.status"
      else
        echo 1 >"$TMPDIR/group-$index.status"
      fi
    }

    maxJobs=${if jobs == null then "\${NIX_BUILD_CORES:-1}" else toString jobs}
    if (( maxJobs < 1 )); then
      maxJobs=$(nproc)
    fi
    for index in "''${!groups[@]}"; do
      while (( $(jobs -rp | wc -l) >= maxJobs )); do
        wait -n
      done
      runGroup "$index" "''${groups[$index]}" &
    done
    wait

    failed=0
    for index in "''${!groups[@]}"; do
      echo "== ''${groups[$index]}"
      cat "$TMPDIR/group-$index.log"
      if [[ $(<"$TMPDIR/group-$index.status") != 0 ]]; then
        failed=1
      fi
    done
    if (( failed )); then
      exit 1
    fi

    ${postCheck}
    touch "$out"
  ''
