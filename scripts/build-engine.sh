#!/usr/bin/env bash
# Builds mcpp-community/mcpp at $MCPP_REF with the released bootstrap mcpp, and
# makes the result $MCPP. The built binary is kept at $LAB_ENGINE_DIR/mcpp with
# the commit it was built from at $LAB_ENGINE_DIR/commit, so that a cache that
# holds both serves the next run with the same commit without a build.
#
# Exports MCPP. Fails unless `$MCPP --version` is `mcpp $ENGINE_VERSION`.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${MCPP_BOOTSTRAP_BIN:?}"
: "${MCPP_REF:?}"
: "${ENGINE_VERSION:?}"
: "${LAB_ENGINE_DIR:?}"

commit="$(git ls-remote https://github.com/mcpp-community/mcpp.git "refs/heads/$MCPP_REF" | cut -f1)"
[ -n "$commit" ] || { echo "::error::mcpp-community/mcpp has no branch $MCPP_REF"; exit 1; }
echo "== mcpp-community/mcpp $MCPP_REF is at $commit"
mkdir -p "$LAB_ENGINE_DIR"

if [ -x "$LAB_ENGINE_DIR/mcpp" ] && [ "$(cat "$LAB_ENGINE_DIR/commit" 2>/dev/null || true)" = "$commit" ]; then
    echo "== the cache holds the engine built from $commit; no build"
    built="$LAB_ENGINE_DIR/mcpp"
else
    src="$LAB_WORK/mcpp-src"
    rm -rf "$src"
    git clone --quiet --depth 1 --branch "$MCPP_REF" https://github.com/mcpp-community/mcpp.git "$src"
    [ "$(git -C "$src" rev-parse HEAD)" = "$commit" ] || echo "note: the branch moved between ls-remote and clone: $(git -C "$src" rev-parse HEAD)"
    commit="$(git -C "$src" rev-parse HEAD)"
    # The clone's .xlings.json pins the mcpp that builds mcpp in that
    # repository's own CI; a build inside the checkout would obey it and install
    # a version this job did not choose.
    rm -f "$src/.xlings.json"
    echo "== building mcpp with the released $("$MCPP_BOOTSTRAP_BIN" --version | head -1)"
    ( cd "$src" && time "$MCPP_BOOTSTRAP_BIN" build )
    found="$(find "$src/target" -type f -name mcpp -perm -u+x)"
    count="$(printf '%s\n' "$found" | grep -c . || true)"
    if [ "$count" != 1 ]; then
        echo "::error::expected one mcpp binary from $MCPP_REF, found $count"
        printf '%s\n' "$found" | sed 's/^/    /'
        exit 1
    fi
    cp "$found" "$LAB_ENGINE_DIR/mcpp"
    chmod +x "$LAB_ENGINE_DIR/mcpp"
    printf '%s\n' "$commit" > "$LAB_ENGINE_DIR/commit"
    built="$LAB_ENGINE_DIR/mcpp"
fi

version="$("$built" --version | head -1)"
echo "== the engine under test: $version at $built (commit $commit)"
[ "$version" = "mcpp $ENGINE_VERSION" ] || { echo "::error::the engine built from $MCPP_REF prints '$version', expected 'mcpp $ENGINE_VERSION'"; exit 1; }
lab_export MCPP "$built"
lab_export MCPP_COMMIT "$commit"
lab_summary "- engine: \`$version\` built from \`mcpp-community/mcpp\` \`$MCPP_REF\` at \`$commit\`"
