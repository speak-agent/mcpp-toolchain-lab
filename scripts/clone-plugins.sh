#!/usr/bin/env bash
# Clones mcpp-community/mcpp-plugins at $PLUGINS_REF, for the cases that need
# `mcpp.plugins.toolchain`. Exports LAB_PLUGINS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${PLUGINS_REF:?}"
dir="$LAB_WORK/mcpp-plugins"
clone_at https://github.com/mcpp-community/mcpp-plugins.git "$PLUGINS_REF" "${PLUGINS_SHA:-}" "$dir"
commit="$(git -C "$dir" rev-parse HEAD)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$dir/mcpp.toml" | head -1)"
echo "== mcpp-community/mcpp-plugins $PLUGINS_REF at $commit, package version $version"
[ -f "$dir/src/toolchain.cppm" ] || { echo "::error::$PLUGINS_REF has no src/toolchain.cppm (mcpp.plugins.toolchain)"; exit 1; }
lab_export LAB_PLUGINS "$dir"
lab_summary "- plugins: \`mcpp-community/mcpp-plugins\` \`$PLUGINS_REF\` at \`$commit\`, version \`$version\`"
