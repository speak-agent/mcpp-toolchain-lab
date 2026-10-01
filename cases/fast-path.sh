# fast-path: the fingerprint and the fast paths depend on the toolchain's own
# programs. Nothing changed: the fast path serves the build. A program of the
# toolchain touched: the next build declines it and says why.
work="$LAB_WORK/fast-path"
lld="$(lld_name)"
[ -e "$LAB_TREE/bin/$lld" ] || skip "the tree has no $lld, which the linker wrapper execs"
mkdir -p "$work"
wrapper="$work/ld-wrapper"
make_ld_wrapper "$LAB_TREE" "$wrapper"

new_project "$work/app"
{
    manifest_head
    echo '[toolchain]'
    echo "default = { path = \"$LAB_TREE\", launcher = \"/usr/bin/env\", tools = { ld = \"$wrapper\" } }"
} > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'

run build
need_success "the first build succeeded"
run_v build -v
need_success "the second build, nothing changed, succeeded"
refuse "fast-path: build declined" "an unchanged build does not decline the fast path"
run_v build -v
need_success "the third build, nothing changed, succeeded"
refuse "fast-path: build declined" "a second unchanged build does not decline the fast path"

# A tool stated by role: touch the wrapper. A sleep first, so the modification
# time differs from the first build's under any clock granularity.
sleep 2
touch "$wrapper"
echo "-- touched $wrapper (mtime $(file_mtime "$wrapper"))"
run_v build -v
need_success "the build after touching the linker wrapper succeeded"
need "a program of the toolchain named by path changed" "touching a tool stated by role is noticed"
run_v build -v
refuse "fast-path: build declined" "the build after that is served by the fast path again"

# The driver itself. The tree's clang++ is a symlink into the payload, and touch
# follows it, so this changes the modification time of the real driver.
sleep 2
touch "$LAB_TREE/bin/clang++"
echo "-- touched $LAB_TREE/bin/clang++ (target mtime $(file_mtime "$LAB_TREE/bin/clang++"))"
run_v build -v
need_success "the build after touching the driver succeeded"
need "a program of the toolchain named by path changed" "touching the driver is noticed"

pass "unchanged builds take the fast path; touching the linker wrapper and touching the driver each decline it with 'a program of the toolchain named by path changed'"
