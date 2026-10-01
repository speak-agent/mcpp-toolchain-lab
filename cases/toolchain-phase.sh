# toolchain-phase: `[toolchain] default = { configure = "build.mcpp" }` makes the
# root build program run twice. In its toolchain phase it states the toolchain
# with mcpp.plugins.toolchain; the bootstrap toolchain (`bootstrap = "llvm@<v>"`)
# compiles and runs it; the build phase of the same program then runs with the
# toolchain it stated.
work="$LAB_WORK/toolchain-phase"
phase_project "$work/app" ""
state_line="$(line_of build.mcpp 'tc::use(')"
layout_line="$(line_of build.mcpp 'tc::layout(')"
echo "-- tc::layout is on build.mcpp:$layout_line, tc::use on build.mcpp:$state_line"

run build
need_success "the build succeeded"
need "Bootstrap llvm@$(regex_escape "$LAB_LLVM_VERSION")" "the output has a Bootstrap line naming llvm@$LAB_LLVM_VERSION"
need "Using toolchain clang [^ ]+ ← $(regex_escape "$LAB_TREE")  \[program · build\.mcpp:${layout_line}\]" \
     "the build reports the toolchain, the tree and [program · build.mcpp:${layout_line}]"
need "lab build phase ran, compiler clang" "the build phase of the same program ran, with the toolchain it stated"
need "Finished .* · program: toolchain" "the Finished line summarises the program-stated toolchain"

res="$(find target -name resolution.json | head -1)"
echo "-- sources recorded in $res:"
json_get "$res" "json.dumps(d['sources'], indent=1)"
cls="$(json_get "$res" "[s['class'] for s in d['sources'] if s['subject']=='toolchain.build'][0]")"
[ "$cls" = program ] || fail "resolution.json records toolchain.build with class '$cls', expected program"
ok "resolution.json records toolchain.build with class: program"

# The program of this project: the toolchain phase states a toolchain and no
# source files besides main.cpp, so the program is the shared one.
run_app

run why toolchain
need '^  source: program · build\.mcpp:' "mcpp why toolchain prints a source: line naming the build program"

pass "the build program stated the tree in its toolchain phase (build.mcpp:${layout_line}); Bootstrap llvm@$LAB_LLVM_VERSION; the build phase ran; the program runs"
