#!/usr/bin/env bash
# Looks for the toolchain release of speak-agent/llvm-macos27-lab: an asset named
# llvm-23.1.2-x1-macos-arm64.tar.xz, which carries the lld with upstream's
# arm64e.x1 fix. When it is published, extracts it and exports LAB_TREE_FROM (the
# directory that holds bin/clang++) and LAB_TREE_SOURCE=lab-asset; when it is
# not, exports LAB_TREE_SOURCE=payload and nothing else.
#
# Needs GH_TOKEN for `gh`.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
repo="speak-agent/llvm-macos27-lab"
asset="${LAB_TOOLCHAIN_ASSET:-llvm-23.1.2-x1-macos-arm64.tar.xz}"

echo "== gh release list -R $repo"
gh release list -R "$repo" || true
tag="$(gh api "repos/$repo/releases" --jq "[.[] | select(any(.assets[]; .name == \"$asset\"))][0].tag_name // empty" 2>/dev/null || true)"
if [ -z "$tag" ]; then
    echo "== no release of $repo has an asset named $asset"
    lab_export LAB_TREE_SOURCE payload
    lab_summary "- toolchain tree: the managed payload (no release asset \`$asset\` in \`$repo\` yet)"
    exit 0
fi
echo "== release $tag of $repo has $asset"
dir="$LAB_WORK/lab-toolchain"
rm -rf "$dir"; mkdir -p "$dir"
gh release download "$tag" -R "$repo" --pattern "$asset" --dir "$dir"
ls -l "$dir"
shasum -a 256 "$dir/$asset"
tar -xJf "$dir/$asset" -C "$dir"
clang="$(find "$dir" -maxdepth 3 -path '*/bin/clang++' | head -1)"
[ -n "$clang" ] || { echo "::error::no bin/clang++ in $asset"; find "$dir" -maxdepth 2 | head -30; exit 1; }
root="$(cd "$(dirname "$clang")/.." && pwd)"
echo "== the lab toolchain tree: $root"
lab_export LAB_TREE_FROM "$root"
lab_export LAB_TREE_SOURCE lab-asset
lab_export LAB_TOOLCHAIN_TAG "$tag"
lab_summary "- toolchain tree: asset \`$asset\` of release \`$tag\` of \`$repo\`"
