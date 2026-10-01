#!/usr/bin/env bash
# Shared helpers. Sourced by every script in this repository.
#
# Written for bash 3.2 (the bash of macOS) and GNU bash alike: no associative
# arrays, no `mapfile`, no `${var,,}`, no GNU-only `touch -d`, `sed -i` or
# `readlink -f`.

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LAB_ROOT

# Messages are asserted on uncoloured text.
export NO_COLOR=1

case "$(uname -s)" in
    Darwin) LAB_OS=macos ;;
    Linux)  LAB_OS=linux ;;
    *)      LAB_OS=other ;;
esac
export LAB_OS
export LAB_PLATFORM="${LAB_PLATFORM:-$LAB_OS}"

# Scratch space for projects and trees; never inside MCPP_HOME or the checkout.
export LAB_WORK="${LAB_WORK:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lab-work}"
mkdir -p "$LAB_WORK"

# lab_export NAME VALUE: set a variable here and for the steps that follow.
lab_export() {
    export "$1=$2"
    if [ -n "${GITHUB_ENV:-}" ]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"
    fi
    # Outside CI: LAB_ENV_FILE=<file> collects the same values as `export` lines,
    # for `. <file>` in the shell that runs the cases.
    if [ -n "${LAB_ENV_FILE:-}" ]; then
        printf 'export %s=%s\n' "$1" "$(printf '%q' "$2")" >> "$LAB_ENV_FILE"
    fi
}

lab_summary() {
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
    fi
}

# Verdicts. A case calls exactly one of pass, fail, skip; each prints one line
# that begins with `VERDICT` so that a log can be searched for them, and the
# line is repeated in the job summary.
CASE="${CASE:-lab}"
verdict() {
    local line="VERDICT ${CASE} [${LAB_PLATFORM}] $1: $2"
    echo "$line"
    lab_summary "- \`${CASE}\` on \`${LAB_PLATFORM}\`: **$1** - $2"
}
pass() { verdict PASS "$*"; exit 0; }
skip() { verdict SKIP "$*"; exit 0; }
# A failure whose cause is a tracked external one is a known-red outcome, and
# only when the output that failed carries the mark of that cause:
#
#   LAB_KNOWN_RED       the issue, e.g. mcpp-community/mcpp#669
#   LAB_KNOWN_RED_MARK  a fixed string the failing output must contain
#
# Set by the xcode-27 job for the steps whose link meets the Xcode 27 SDK with
# an lld that cannot read it. A failure without the mark is a FAIL as ever.
fail() {
    echo "FAIL: $*"
    if [ -n "${out:-}" ]; then
        echo "---- the last output captured"
        printf '%s\n' "$out"
        echo "----"
    fi
    if [ -n "${LAB_KNOWN_RED:-}" ] && [ -n "${LAB_KNOWN_RED_MARK:-}" ] \
        && printf '%s\n' "${out:-}" | grep -Fq -- "$LAB_KNOWN_RED_MARK"; then
        verdict KNOWN-RED "$LAB_KNOWN_RED, the output contains '$LAB_KNOWN_RED_MARK': $*"
        exit 0
    fi
    verdict FAIL "$*"
    exit 1
}
ok() { echo "  ok: $*"; }

# run <mcpp args...>: runs $MCPP in the current directory, sets `out` (stdout
# and stderr together) and `rc`, and prints both so the log holds the evidence.
run() {
    echo "\$ mcpp $*"
    set +e
    out="$("$MCPP" "$@" 2>&1)"
    rc=$?
    set -e
    printf '%s\n' "$out" | sed 's/^/    | /'
    echo "    (exit $rc)"
}

# run_v <mcpp args...>: like run, for a verbose build. The assertions read all
# of the output; the log shows the lines about the decisions, because a verbose
# build prints every compiler and linker command line.
run_v() {
    echo "\$ mcpp $*"
    set +e
    out="$("$MCPP" "$@" 2>&1)"
    rc=$?
    set -e
    local total shown
    total="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    printf '%s\n' "$out" | grep -E 'fast-path|fingerprint|Using toolchain|Bootstrap|Finished|Compiling|error|warning|ninja: no work' | cut -c1-300 | sed 's/^/    | /'
    echo "    ($total lines of output; the lines about decisions are shown; exit $rc)"
}

# has <extended-regex>: true when `out` holds a matching line.
has() { grep -Eq -- "$1" <<<"$out"; }

# need <extended-regex> <what>: asserts `out` holds a matching line.
need() {
    if has "$1"; then ok "$2"; else fail "$2 -- no line of the output matches: $1"; fi
}
# refuse <extended-regex> <what>: asserts `out` holds no matching line.
refuse() {
    if has "$1"; then fail "$2 -- a line of the output matches: $1"; else ok "$2"; fi
}
# need_success / need_refusal: the exit status of the last `run`.
need_success() { if [ "$rc" = 0 ]; then ok "$1"; else fail "expected: $1; mcpp exited $rc"; fi; }
need_refusal() { if [ "$rc" != 0 ]; then ok "$1 (exit $rc)"; else fail "expected: $1; mcpp exited 0"; fi; }

# regex_escape <text>: the text, escaped for an extended regular expression.
regex_escape() { printf '%s' "$1" | sed -e 's#[][\.*^$+?(){}|/]#\\&#g'; }

# line_of <file> <fixed text>: the number of the first line that contains it.
line_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }

# The shared C++ program every project builds.
lab_app_source() { cat "$LAB_ROOT/fixtures/app/src/main.cpp"; }
LAB_APP_OUTPUT='toolchain-lab: sum=6 count=3 greeting=hello 42'

# new_project <dir>: an empty project with the shared program; the case writes
# mcpp.toml. Leaves the shell in <dir>.
new_project() {
    rm -rf "$1"
    mkdir -p "$1/src"
    cp "$LAB_ROOT/fixtures/app/src/main.cpp" "$1/src/main.cpp"
    cd "$1"
}

# manifest_head: the [package] table every project starts with.
manifest_head() {
    cat <<'TOML'
[package]
name    = "lab-app"
version = "0.1.0"

TOML
}

# run_app: runs the program the build produced and checks what it prints.
run_app() {
    local bin
    bin="$(find target -type f -name lab-app -perm -u+x | head -1)"
    [ -n "$bin" ] || fail "no program lab-app under target/"
    local got
    got="$("./$bin")" || fail "the program exited non-zero"
    echo "    program printed: $got"
    [ "$got" = "$LAB_APP_OUTPUT" ] || fail "the program printed '$got', expected '$LAB_APP_OUTPUT'"
    ok "the program ran and printed what it should"
}

# json_get <file> <python expression over `d`>: a value of a JSON file. Python 3
# is on every GitHub-hosted runner this repository uses.
json_get() {
    python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
try:
    v = eval(sys.argv[2])
except Exception as e:
    v = "<" + type(e).__name__ + ": " + str(e) + ">"
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

# cfg_snapshot <dir...>: every `*.cfg` under the directories, following
# symlinks, with its size and modification time.
cfg_snapshot() {
    local d
    for d in "$@"; do
        find -L "$d" -name '*.cfg' -type f 2>/dev/null | sort | while IFS= read -r f; do
            printf '%s\t%s\t%s\n' "$f" "$(wc -c < "$f" | tr -d ' ')" "$(file_mtime "$f")"
        done
    done
}

# file_mtime <path>: seconds since the epoch, on GNU and BSD stat alike.
file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# payload_root: the installed managed LLVM payload (newest version).
payload_root() {
    local base="${MCPP_HOME:-$HOME/.mcpp}/registry/data/xpkgs/xim-x-llvm"
    [ -d "$base" ] || return 1
    local v
    v="$(ls -1 "$base" | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    [ -n "$v" ] || return 1
    printf '%s/%s\n' "$base" "$v"
}

# make_tree <payload> <dest>: the directory a hand-extracted LLVM release looks
# like. bin/ holds a symlink for every program of the payload's bin/ except the
# `*.cfg` files, and include, lib, share and libexec are symlinks.
make_tree() {
    local payload="$1" dest="$2" f d
    rm -rf "$dest"
    mkdir -p "$dest/bin"
    for f in "$payload"/bin/*; do
        case "$f" in
            *.cfg) ;;
            *) ln -s "$f" "$dest/bin/$(basename "$f")" ;;
        esac
    done
    for d in include lib share libexec; do
        if [ -e "$payload/$d" ]; then ln -s "$payload/$d" "$dest/$d"; fi
    done
}

# The lld a wrapper script execs: ld64.lld on macOS, ld.lld elsewhere.
lld_name() {
    if [ "$LAB_OS" = macos ]; then echo ld64.lld; else echo ld.lld; fi
}

# make_ld_wrapper <tree> <dest>: a script that execs the tree's lld, and appends
# a line to <dest>.ran each time it runs, so that a case can tell whether the
# linker it stated took part in the link.
make_ld_wrapper() {
    local lld
    lld="$(lld_name)"
    [ -e "$1/bin/$lld" ] || return 1
    rm -f "$2.ran"
    printf '#!/bin/sh\necho ran >> "%s.ran"\nexec "%s/bin/%s" "$@"\n' "$2" "$1" "$lld" > "$2"
    chmod +x "$2"
}

# tree_ready: asserts the environment a case needs.
tree_ready() {
    : "${MCPP:?MCPP names the engine under test}"
    : "${LAB_TREE:?LAB_TREE names the toolchain tree; run scripts/make-tree.sh first}"
    [ -x "$LAB_TREE/bin/clang++" ] || { echo "no clang++ in $LAB_TREE/bin"; exit 2; }
}

# phase_project <dir> <statement>: a project whose root build program states the
# toolchain in its toolchain phase, with the library of mcpp-plugins
# (`mcpp.plugins.toolchain`, feature `plugins-toolchain`). <statement> is C++ run
# in the toolchain phase before `tc::use(...)`. The build phase prints a warning
# naming the compiler, which is how a case sees that the phase ran. Leaves the
# shell in <dir>.
#
# LAB_PLUGINS is a clone of mcpp-plugins at the reference under test; a path
# dependency is declared by an absolute path, in the host's own syntax.
phase_project() {
    : "${LAB_PLUGINS:?LAB_PLUGINS names the clone of mcpp-plugins}"
    : "${LAB_LLVM_VERSION:?the payload version names the bootstrap}"
    new_project "$1"
    {
        manifest_head
        cat <<TOML
[toolchain]
default   = { configure = "build.mcpp" }
bootstrap = "llvm@$LAB_LLVM_VERSION"

[build-dependencies.mcpp]
plugins = { path = "$LAB_PLUGINS", features = ["plugins-toolchain"], host-module = true }
TOML
    } > mcpp.toml
    cat > build.mcpp <<CPP
import std;
import mcpp;
import mcpp.plugins.toolchain;
namespace tc = mcpp::plugins::toolchain;

int main() {
    if (tc::configure([] {
$2
            auto d = tc::layout("$LAB_TREE");
            tc::use(d);
        }))
        return 0;
    // The build phase of the same program.
    mcpp::warning((std::string("lab build phase ran, compiler ") + mcpp::compiler()).c_str());
    return 0;
}
CPP
    echo "-- mcpp.toml"; sed 's/^/     /' mcpp.toml
    echo "-- build.mcpp"; cat -n build.mcpp | sed 's/^/     /'
}

# clone_at <url> <ref> <sha> <dest>: a shallow clone of <ref>, or of the commit
# <sha> when one is given. The commits a run measures are resolved once, by the
# first job, so that every job of the run measures the same ones even when a
# branch moves while the run is going.
clone_at() {
    local url="$1" ref="$2" sha="$3" dest="$4"
    rm -rf "$dest"
    if [ -n "$sha" ]; then
        git init -q "$dest"
        git -C "$dest" remote add origin "$url"
        git -C "$dest" fetch -q --depth 1 origin "$sha"
        git -C "$dest" checkout -q FETCH_HEAD
    else
        git clone -q --depth 1 --branch "$ref" "$url" "$dest"
    fi
}
