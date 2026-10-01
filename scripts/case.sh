#!/usr/bin/env bash
# Runs one case: scripts/case.sh <name>. The case is cases/<name>.sh; it is
# sourced after lib.sh, so it has the helpers and ends in pass, fail or skip.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export CASE="${1:?usage: case.sh <case name>}"
source "$here/lib.sh"
file="$LAB_ROOT/cases/$CASE.sh"
[ -f "$file" ] || { echo "no such case: $CASE"; exit 2; }
tree_ready
echo "######## case $CASE on $LAB_PLATFORM"
echo "engine:  $MCPP ($("$MCPP" --version | head -1))"
echo "tree:    $LAB_TREE"
echo "payload: ${LAB_PAYLOAD:-unknown} (${LAB_LLVM_VERSION:-unknown})"
source "$file"
