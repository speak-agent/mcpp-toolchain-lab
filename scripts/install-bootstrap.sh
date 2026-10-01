#!/usr/bin/env bash
# Installs the released mcpp $MCPP_BOOTSTRAP from its GitHub release asset, and
# prepares $MCPP_HOME for it.
#
# Exports MCPP_BOOTSTRAP_BIN (the released mcpp) and MCPP_VENDORED_XLINGS (the
# xlings the release carries).
#
# A released mcpp is self-contained: with no MCPP_HOME it uses its own
# directory. MCPP_HOME is pinned inside the workspace here so that actions/cache
# can keep it, and a pinned home moves the place mcpp looks for xlings, so the
# bundled xlings is named explicitly; mcpp copies it into the home on the first
# call and answers from there afterwards.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${MCPP_BOOTSTRAP:?}"
: "${MCPP_HOME:?}"

case "$LAB_OS-$(uname -m)" in
    linux-x86_64) asset=linux-x86_64.tar.gz;  suffix=linux-x86_64 ;;
    macos-arm64)  asset=macosx-arm64.tar.gz;  suffix=macosx-arm64 ;;
    *) echo "::error::no released mcpp for $LAB_OS-$(uname -m)"; exit 1 ;;
esac
dest="${RUNNER_TEMP:-/tmp}/mcpp-bootstrap"
rm -rf "$dest"; mkdir -p "$dest"
url="https://github.com/mcpp-community/mcpp/releases/download/v${MCPP_BOOTSTRAP}/mcpp-${MCPP_BOOTSTRAP}-${asset}"
echo "== fetching $url"
curl -L -fsS --retry 3 --retry-all-errors -o "$dest/mcpp.tar.gz" "$url"
tar -xzf "$dest/mcpp.tar.gz" -C "$dest"
boot="$dest/mcpp-${MCPP_BOOTSTRAP}-${suffix}/bin/mcpp"
xl="$dest/mcpp-${MCPP_BOOTSTRAP}-${suffix}/registry/bin/xlings"
[ -x "$boot" ] || { echo "::error::no mcpp at $boot"; ls -R "$dest" | head -30; exit 1; }
[ -f "$xl" ] || { echo "::error::no vendored xlings at $xl"; exit 1; }
export MCPP_VENDORED_XLINGS="$xl"
echo "== the released mcpp: $("$boot" --version | head -1)"
mkdir -p "$MCPP_HOME"
"$boot" self config --mirror GLOBAL
lab_export MCPP_BOOTSTRAP_BIN "$boot"
lab_export MCPP_VENDORED_XLINGS "$xl"
lab_summary "- bootstrap: released \`$("$boot" --version | head -1)\`"
