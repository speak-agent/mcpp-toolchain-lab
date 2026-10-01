# path-llvm: `[toolchain] default = { path = "<tree>" }` names a toolchain mcpp
# did not install. mcpp probes the drivers in <tree>/bin, drives them with its
# own link line, writes nothing into the tree, and says where the toolchain
# came from.
work="$LAB_WORK/path-llvm"
new_project "$work/app"
{
    manifest_head
    echo '[toolchain]'
    echo "default = { path = \"$LAB_TREE\" }"
} > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'
decl_line="$(line_of mcpp.toml 'default = {')"

# What is in the tree and in the payload before the build, so that "nothing was
# written" is a comparison and not an absence of evidence. The tree's lib,
# include and share are symlinks into the payload, so the payload is covered
# too.
before_tree="$(cfg_snapshot "$LAB_TREE")"
before_payload="$(cfg_snapshot "$LAB_PAYLOAD/bin")"
echo "-- *.cfg files reachable from the tree before the build:"; printf '%s\n' "$before_tree" | sed 's/^/     /'

run build
need_success "the build succeeded"
need "Using toolchain clang [^ ]+ ← $(regex_escape "$LAB_TREE")  \[custom · mcpp\.toml:${decl_line}\]" \
     "the build reports the toolchain, the tree and [custom · mcpp.toml:${decl_line}]"
need "Finished .* · custom: toolchain" "the Finished line summarises the custom toolchain"
run_app

res="$(find target -name resolution.json | head -1)"
[ -n "$res" ] || fail "no resolution.json under target/"
echo "-- sources recorded in $res:"
json_get "$res" "json.dumps(d['sources'], indent=1)"
cls="$(json_get "$res" "[s['class'] for s in d['sources'] if s['subject']=='toolchain.build'][0]")"
[ "$cls" = custom ] || fail "resolution.json records toolchain.build with class '$cls', expected custom"
ok "resolution.json records toolchain.build with class: custom"
val="$(json_get "$res" "[s['value'] for s in d['sources'] if s['subject']=='toolchain.build'][0]")"
[ "$val" = "$LAB_TREE" ] || fail "toolchain.build records '$val', expected the tree $LAB_TREE"
ok "toolchain.build names the tree"

run why toolchain
need '^  source: custom · mcpp\.toml:' "mcpp why toolchain prints a source: line"

after_tree="$(cfg_snapshot "$LAB_TREE")"
after_payload="$(cfg_snapshot "$LAB_PAYLOAD/bin")"
[ -z "$(find "$LAB_TREE" -name '*.cfg')" ] || fail "a *.cfg file exists under $LAB_TREE: $(find "$LAB_TREE" -name '*.cfg')"
[ "$before_tree" = "$after_tree" ] || fail "the *.cfg files reachable from the tree changed: before=[$before_tree] after=[$after_tree]"
[ "$before_payload" = "$after_payload" ] || fail "the payload's *.cfg files changed: before=[$before_payload] after=[$after_payload]"
ok "no *.cfg file was created under the tree, and none of the files reachable from it changed"

pass "built with a path-named LLVM tree; reported custom at mcpp.toml:${decl_line}; resolution.json class custom; no cfg written"
