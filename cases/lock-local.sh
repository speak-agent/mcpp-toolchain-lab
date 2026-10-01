# lock-local: where the toolchain named by path is recorded.
#
# The property looked for is that mcpp.lock records the toolchain as `local`
# (SPEC-006 section 2.2.1 of the engine, as it stood until the engine commit
# 11431544, which withdrew the statement), or that the message of a build on a
# machine without the tree says so. When the lock does not carry it, the case
# records precisely what the lock does carry and what the build says, and ends
# in RECORDED: it asserts no property that the engine does not state. What it
# does assert, because every statement of the engine makes it, is that the lock
# is written, that it holds the resolved dependency, and that a machine without
# the tree is refused, naming the tree, where the declaration is read.
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

# The word is searched for outside any path: a path may hold it by chance.
no_paths() { sed -e "s|$tree||g" -e "s|$work||g"; }
absent=""
if no_paths < mcpp.lock | grep -Eqi '(^|[^A-Za-z])local([^A-Za-z]|$)'; then
    ok "mcpp.lock records a local entry"
else
    absent="${absent}mcpp.lock holds no local entry; "
    echo "NOT CARRIED: no line of mcpp.lock says local"
fi
if grep -qi 'toolchain' mcpp.lock; then
    ok "mcpp.lock mentions the toolchain"
else
    absent="${absent}mcpp.lock does not mention the toolchain; "
    echo "NOT CARRIED: the word toolchain does not occur in mcpp.lock"
fi
echo "-- what mcpp.lock carries: $(grep -c '^\[package' mcpp.lock) package table(s), $(grep -c '^\[index' mcpp.lock) index table(s)"

# What the build record carries instead: the source class, and the runtime
# closure's own notion of what is machine-local.
res="$(find target -name resolution.json | head -1)"
echo "-- occurrences of machine_local in the build record: $(grep -c machine_local "$res")"
echo "-- resolution.json: sources and toolchain"
json_get "$res" "json.dumps({'sources': [{k: s[k] for k in ('subject','class','value')} for s in d['sources']], 'toolchain': d['toolchain']}, indent=1)"

# A machine without the tree.
mv "$tree" "$tree.gone"
run build
mv "$tree.gone" "$tree"
need_refusal "a build without the tree is refused"
need "$(regex_escape "$tree")" "the refusal names the tree"
need "no C\\+\\+ driver in bin/" "the refusal says the tree has no C++ driver in bin/"
if printf '%s\n' "$out" | no_paths | grep -Eqi '(^|[^A-Za-z])local([^A-Za-z]|$)'; then
    ok "the refusal says the toolchain is local"
else
    absent="${absent}the refusal for a missing tree does not say local; "
    echo "NOT CARRIED: the message of a build without the tree does not say local"
fi

if [ -z "$absent" ]; then
    pass "mcpp.lock and the missing-tree message record the toolchain as local"
fi
recorded "the toolchain is not recorded as local: ${absent}mcpp.lock carries only the resolved dependency; the build record (resolution.json) carries class custom; a machine without the tree is refused naming the tree"
