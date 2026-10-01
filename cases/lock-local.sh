# lock-local: what a build records about a toolchain named by path, and what a
# machine without the tree is told.
#
# THE ENGINE DOES NOT RECORD A TOOLCHAIN IN mcpp.lock, and states so (engine
# commit 11431544: the lock holds the result of dependency resolution, a
# toolchain is not a resolved dependency). Until then its documentation said the
# lock records the toolchain as `local`, which is what this case first expected;
# it failed, and the case was restated to assert what the engine states:
#
#   - mcpp.lock is written and holds the resolved dependency;
#   - a machine that does not have the tree is refused where the declaration is
#     read, naming the tree, and not built with another toolchain.
#
# What mcpp.lock and the build record (resolution.json) do carry is printed, so
# that a change in either shows in the log.
work="$LAB_WORK/lock-case"
mkdir -p "$work"
# A private tree, so that taking it away does not disturb any other case.
tree="$work/llvm-tree"
make_tree "$LAB_PAYLOAD" "$tree"

# A version dependency, so that the build has something to lock: a build whose
# graph holds no index package writes no mcpp.lock at all.
new_project "$work/app"
{
    manifest_head
    echo '[toolchain]'
    echo "default = { path = \"$tree\" }"
    echo
    echo '[dependencies]'
    echo 'cmdline = "0.0.2"'
} > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'

run build
need_success "the build with the path-named toolchain and one index dependency succeeded"
[ -f mcpp.lock ] || fail "the build wrote no mcpp.lock"
echo "-- mcpp.lock:"; sed 's/^/     /' mcpp.lock
grep -q '^\[package."cmdline"\]' mcpp.lock || fail "mcpp.lock does not hold the resolved dependency cmdline"
ok "mcpp.lock holds the resolved dependency"

# What the lock carries, for the record.
echo "-- what mcpp.lock carries: $(grep -c '^\[package' mcpp.lock) package table(s), $(grep -c '^\[index' mcpp.lock) index table(s); lines naming a toolchain: $(grep -ci 'toolchain' mcpp.lock)"

# What the build record carries: the source class, and the runtime closure's own
# notion of what is machine-local.
res="$(find target -name resolution.json | head -1)"
echo "-- occurrences of machine_local in the build record: $(grep -c machine_local "$res")"
echo "-- resolution.json: sources and toolchain"
json_get "$res" "json.dumps({'sources': [{k: s[k] for k in ('subject','class','value')} for s in d['sources']], 'toolchain': d['toolchain']}, indent=1)"
cls="$(json_get "$res" "[s['class'] for s in d['sources'] if s['subject']=='toolchain.build'][0]")"
[ "$cls" = custom ] || fail "resolution.json records toolchain.build with class '$cls', expected custom"
ok "the build record holds the toolchain with class: custom"

# A machine without the tree.
mv "$tree" "$tree.gone"
run build
mv "$tree.gone" "$tree"
need_refusal "a build without the tree is refused"
need "$(regex_escape "$tree")" "the refusal names the tree"
need "no C\\+\\+ driver in bin/" "the refusal says the tree has no C++ driver in bin/"
refuse '^ *Finished' "no build finished with another toolchain"

pass "mcpp.lock holds the resolved dependency and, as the engine states, no toolchain; the build record holds the toolchain as custom; a build without the tree is refused naming the tree"
