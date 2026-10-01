# env-path: the same project with no [toolchain] table, and the toolchain named
# for this one build by MCPP_TOOLCHAIN=path:<tree>.
work="$LAB_WORK/env-path"
new_project "$work/app"
manifest_head > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'
! grep -q '\[toolchain\]' mcpp.toml || fail "the manifest of this case must have no [toolchain] table"

echo "\$ MCPP_TOOLCHAIN=path:$LAB_TREE mcpp build"
export MCPP_TOOLCHAIN="path:$LAB_TREE"
run build
need_success "the build succeeded"
need "Using toolchain clang [^ ]+ ← $(regex_escape "$LAB_TREE")  \[custom · env MCPP_TOOLCHAIN\]" \
     "the build reports [custom · env MCPP_TOOLCHAIN]"
need "Finished .* · custom: toolchain" "the Finished line summarises the custom toolchain"
run_app

res="$(find target -name resolution.json | head -1)"
origin="$(json_get "$res" "[s['origin'] for s in d['sources'] if s['subject']=='toolchain.build'][0]")"
echo "-- origin recorded for toolchain.build: $origin"

# Without the variable the same project builds with the default toolchain, which
# shows that the variable, not the tree, chose it.
unset MCPP_TOOLCHAIN
run build
need_success "the build without the variable succeeded"
refuse "Using toolchain .*\[custom" "without the variable no custom toolchain is reported"

pass "MCPP_TOOLCHAIN=path:<tree> chose the toolchain for one build and was reported as [custom · env MCPP_TOOLCHAIN]"
