# managed-only: `--managed-only` (and MCPP_MANAGED_ONLY=1) refuses a build whose
# toolchain is not the ecosystem's, naming it.
work="$LAB_WORK/managed-only"
new_project "$work/app"
{
    manifest_head
    echo '[toolchain]'
    echo "default = { path = \"$LAB_TREE\" }"
} > mcpp.toml
cat mcpp.toml | sed 's/^/    toml| /'

run build --managed-only
need_refusal "--managed-only refuses a build that uses a path-named toolchain"
need "toolchain" "the message names the toolchain"
need "$(regex_escape "$LAB_TREE")" "the message names the tree"
refuse '^ *Finished' "no build finished"
flag_out="$out"

echo "\$ MCPP_MANAGED_ONLY=1 mcpp build"
export MCPP_MANAGED_ONLY=1
run build
unset MCPP_MANAGED_ONLY
need_refusal "MCPP_MANAGED_ONLY=1 refuses it too"
need "toolchain" "the message names the toolchain"

# The same project without the option builds: the refusal is the option's.
run build
need_success "the same project builds without --managed-only"

pass "--managed-only and MCPP_MANAGED_ONLY=1 refused the path-named toolchain and named it; without them the project builds"
