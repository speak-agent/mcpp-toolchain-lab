# lock-local: mcpp.lock records the toolchain as `local` (toolchain-management
# spec 2.2.1), and a build on a machine without the tree says so. The case
# asserts that, and when the lock does not carry it, it records what the lock
# does carry and what the build says without the tree.
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

problems=""
# The word is searched for outside any path: a path may hold it by chance.
no_paths() { sed -e "s|$tree||g" -e "s|$work||g"; }
if no_paths < mcpp.lock | grep -Eqi '(^|[^A-Za-z])local([^A-Za-z]|$)'; then
    ok "mcpp.lock records a local entry"
else
    problems="${problems}mcpp.lock does not record the toolchain as local; "
    echo "FINDING: no line of mcpp.lock says local"
fi
if grep -qi 'toolchain' mcpp.lock; then
    ok "mcpp.lock mentions the toolchain"
else
    problems="${problems}mcpp.lock does not mention the toolchain at all; "
    echo "FINDING: the word toolchain does not occur in mcpp.lock"
fi
echo "-- what mcpp.lock carries: $(grep -c '^\[package' mcpp.lock) package table(s), $(grep -c '^\[index' mcpp.lock) index table(s)"

# What the build record carries instead: the source class, and the runtime
# closure's own notion of what is machine-local.
echo "-- occurrences of machine_local in the build record: $(grep -c machine_local "$(find target -name resolution.json | head -1)")"
# What the build record carries instead.
res="$(find target -name resolution.json | head -1)"
echo "-- resolution.json: sources and toolchain"
json_get "$res" "json.dumps({'sources': [{k: s[k] for k in ('subject','class','value')} for s in d['sources']], 'toolchain': d['toolchain']}, indent=1)"

# A machine without the tree.
mv "$tree" "$tree.gone"
run build
mv "$tree.gone" "$tree"
need_refusal "a build without the tree is refused"
need "$(regex_escape "$tree")" "the refusal names the tree"
if printf '%s\n' "$out" | no_paths | grep -Eqi '(^|[^A-Za-z])local([^A-Za-z]|$)'; then
    ok "the refusal says the toolchain is local"
else
    problems="${problems}the refusal for a missing tree does not say local; "
    echo "FINDING: the message of a build without the tree does not say local"
fi

[ -z "$problems" ] || fail "the toolchain is not recorded as local: ${problems}(what mcpp.lock and the missing-tree message carry is printed above)"
pass "mcpp.lock and the missing-tree message record the toolchain as local"
