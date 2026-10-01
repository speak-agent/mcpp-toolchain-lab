#!/usr/bin/env bash
# Builds the toolchain tree the cases name by path, from the managed LLVM
# payload of $MCPP_HOME, without the files mcpp generates.
#
# The payload's bin/ holds, besides the programs, the `*.cfg` files mcpp writes
# when it installs the payload. The tree has symlinks to every program EXCEPT
# those files, and symlinks for include, lib, share and libexec: the shape of an
# LLVM release package extracted by hand. A path-named toolchain is a directory
# like this one.
#
# Environment: MCPP (the engine), MCPP_HOME, LAB_PLATFORM, LAB_LLVM_SPEC (the
# managed spec to install when the home holds no LLVM payload),
# LAB_TREE_FROM (a directory that already is a toolchain tree; it is used as it
# is, and the payload is still located for the bootstrap of toolchain-phase).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${MCPP:?}"
: "${MCPP_HOME:?}"

echo "== managed toolchains of this home"
"$MCPP" toolchain list || true

payload="$(payload_root || true)"
if [ -z "$payload" ]; then
    spec="${LAB_LLVM_SPEC:-llvm@22.1.8}"
    echo "== no LLVM payload in $MCPP_HOME; installing $spec"
    "$MCPP" toolchain install "$spec"
    payload="$(payload_root || true)"
fi
[ -n "$payload" ] || { echo "::error::no LLVM payload under $MCPP_HOME after the install"; exit 1; }
version="$(basename "$payload")"
echo "== the installed LLVM payload: $payload (version $version)"
echo "-- programs in the payload's bin/ (cfg files are what mcpp generates)"
ls -1 "$payload/bin" | sed 's/^/     /'

tree="$LAB_WORK/llvm-tree"
if [ -n "${LAB_TREE_FROM:-}" ]; then
    tree="$LAB_TREE_FROM"
    echo "== using a prebuilt toolchain tree: $tree"
else
    make_tree "$payload" "$tree"
fi

echo "== the toolchain tree: $tree"
ls -l "$tree" | sed 's/^/     /'
echo "-- $tree/bin"
ls -1 "$tree/bin" | sed 's/^/     /'
cfgs="$(find "$tree/bin" -name '*.cfg' | wc -l | tr -d ' ')"
echo "-- *.cfg files in the tree's bin/: $cfgs"
if [ -z "${LAB_TREE_FROM:-}" ]; then
    [ "$cfgs" = 0 ] || { echo "::error::the tree holds $cfgs cfg files"; exit 1; }
fi
echo "-- the driver's version"
"$tree/bin/clang++" --version

lab_export LAB_TREE "$tree"
lab_export LAB_PAYLOAD "$payload"
lab_export LAB_LLVM_VERSION "$version"
