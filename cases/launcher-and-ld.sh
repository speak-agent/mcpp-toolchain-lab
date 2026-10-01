# launcher-and-ld: a launcher in front of the compiler, and a linker stated by
# role as a wrapper script that execs the tree's lld.
work="$LAB_WORK/launcher-and-ld"
lld="$(lld_name)"
[ -e "$LAB_TREE/bin/$lld" ] || skip "the tree has no $lld, which the linker wrapper execs"
[ -x /usr/bin/env ] || skip "/usr/bin/env is not present, and it is the pass-through launcher"
mkdir -p "$work"
wrapper="$work/ld-wrapper"
make_ld_wrapper "$LAB_TREE" "$wrapper"
echo "-- the linker wrapper $wrapper:"; sed 's/^/     /' "$wrapper"

new_project "$work/app"
{
    manifest_head
    echo '[toolchain]'
    echo "default = { path = \"$LAB_TREE\", launcher = \"/usr/bin/env\", tools = { ld = \"$wrapper\" } }"
} > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'

run build
need_success "the build succeeded"
need "Using toolchain clang [^ ]+ ← $(regex_escape "$LAB_TREE")  \[custom · mcpp\.toml:[0-9]+\]" "the toolchain is reported"
ninja="$(find target -name build.ninja | head -1)"
[ -n "$ninja" ] || fail "no build.ninja under target/"
echo "-- compiler lines of $ninja:"
grep -nE '^(cxx|cc) *=' "$ninja" | sed 's/^/     /' || true
echo "-- the link options of $ninja, as written (ldflags, with the build directory left out):"
grep -E '^ldflags *=' "$ninja" | head -1 | cut -c1-1500 | sed 's/^/     /' || true
grep -Eq "^cxx *= /usr/bin/env $(regex_escape "$LAB_TREE")/bin/clang\+\+" "$ninja" \
    || fail "build.ninja does not put /usr/bin/env in front of $LAB_TREE/bin/clang++ (see the cxx lines above)"
ok "build.ninja has the launcher in front of the compiler"

# The stated linker: named in the link options, and run by the link. Both are
# looked at before either is asserted, so that a failure reports what it saw.
named=no; ran=no
grep -Fq -- "--ld-path=$wrapper" "$ninja" && named=yes
[ -s "$wrapper.ran" ] && ran=yes
echo "-- --ld-path=$wrapper in the link options: $named"
echo "-- the linker wrapper ran during the link: $ran"
[ "$named" = yes ] || fail "build.ninja does not name --ld-path=$wrapper (the wrapper ran during the link: $ran)"
ok "build.ninja names --ld-path= with the wrapper"
[ "$ran" = yes ] || fail "the linker wrapper $wrapper did not run during the link"
ok "the linker wrapper ran during the link"
run_app
pass "launcher /usr/bin/env precedes the compiler and --ld-path names the wrapper; the program runs"
