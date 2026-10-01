# toolchain-phase-lab-lld: the toolchain-phase case, on a host whose SDK the
# managed LLVM's lld cannot read, with the bootstrap's lld replaced by the lld of
# the lab toolchain for the duration of the case.
#
# `bootstrap` accepts a managed spec only, so the build program of the toolchain
# phase is linked by the managed LLVM's lld, whatever tree the phase states. On
# the xcode-27 image that lld meets an SDK it cannot read (mcpp-community/mcpp#669)
# before the stated toolchain is ever used, and the toolchain-phase case ends
# KNOWN-RED. This case removes that cause and nothing else: the lld files of the
# managed payload are replaced by the lab's lld, the toolchain-phase case runs
# unchanged, and the originals are put back. It answers whether the toolchain
# phase works on the image once the bootstrap can link.
[ "${LAB_TREE_SOURCE:-}" = lab-asset ] || skip "the tree is not the lab asset, so there is no lld that reads the SDK to put in the bootstrap"
[ -x "$LAB_TREE/bin/lld" ] || skip "the lab tree has no bin/lld"

real() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
targets=""
for n in lld ld64.lld; do
    [ -e "$LAB_PAYLOAD/bin/$n" ] || continue
    t="$(real "$LAB_PAYLOAD/bin/$n")"
    case " $targets " in *" $t "*) ;; *) targets="$targets $t" ;; esac
done
[ -n "$targets" ] || skip "the managed payload has no lld"

restore() {
    for t in $targets; do
        if [ -f "$t.lab-orig" ]; then mv -f "$t.lab-orig" "$t"; fi
    done
    echo "-- the managed payload's lld files are restored"
}
trap restore EXIT
# `lld` answers --version under the name ld64.lld only; the name picks the flavour.
version_of() { "$LAB_PAYLOAD/bin/ld64.lld" --version 2>&1 | head -1; }
echo "-- the lld the bootstrap links with: $(version_of)"
for t in $targets; do
    cp -p "$t" "$t.lab-orig"
    echo "-- replacing $t with the lab's $LAB_TREE/bin/lld"
    cp -f "$LAB_TREE/bin/lld" "$t"
    chmod +x "$t"
done
echo "-- the lld the bootstrap links with now: $(version_of)"
echo "-- the lab tree's own: $("$LAB_TREE/bin/ld64.lld" --version 2>&1 | head -1)"

source "$LAB_ROOT/cases/toolchain-phase.sh"
