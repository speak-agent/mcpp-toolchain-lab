# phase-refuses-a-flag: the toolchain phase may state the toolchain and nothing
# else. A flag stated there is refused, by name.
work="$LAB_WORK/phase-refuses-a-flag"
phase_project "$work/app" '            mcpp::cxxflag("-DX");'
run build
need_refusal "a build whose toolchain phase states a flag is refused"
need 'mcpp:cxxflag=' "the message names mcpp:cxxflag="
refuse '^ *Finished' "no build finished"
pass "a flag stated in the toolchain phase was refused, and the message names mcpp:cxxflag="
