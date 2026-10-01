# mcpp-toolchain-lab

A validation repository. It establishes, by continuous integration on GitHub-hosted runners and from a consumer's point of view, that an [mcpp](https://github.com/mcpp-community/mcpp) project can use a toolchain that mcpp did not install, and that a build program can choose that toolchain.

## What this validates

The behaviour comes from mcpp-community/mcpp#755 and is described in `docs/specs/toolchain-management.md` section 2.2.1 of that repository.

1. `[toolchain] default = { path = "<dir>", prefix, sysroot, family, launcher, tools = { ld = ... } }` in `mcpp.toml`, and `MCPP_TOOLCHAIN=path:<dir>` for one build. The drivers live in `<dir>/bin` (`clang++` for llvm, `g++` for gcc, under `prefix` when stated). mcpp probes them, drives them with its own link line, and writes nothing into the tree.
2. `[toolchain] bootstrap = "<spec>"` names the toolchain that compiles and runs build programs.
3. `[toolchain] default = { configure = "build.mcpp" }` runs the root build program twice. In its toolchain phase (`mcpp::phase()` is `"toolchain"`) the program states the toolchain with `mcpp::toolchain(key, value)` or, from the plugins package, with `mcpp::plugins::toolchain::{configure, layout, use, with_launcher, env}` (feature `plugins-toolchain`). The phase may state nothing else: a flag stated there is refused by name.
4. A build reports a non-default source: `Using toolchain clang <ver> ← <dir>  [custom · mcpp.toml:<line>]` (or `[program · build.mcpp:<line>]` when the build program chose it), a `Bootstrap` line when the bootstrap toolchain differs, and a `Finished ... · custom: toolchain` summary. `mcpp why toolchain` prints a `source:` line, and `target/<triple>/<fingerprint>/resolution.json` records the source under `sources`.
5. The fingerprint and the fast paths depend on the toolchain's own programs. Rebuilding or touching the driver, or a tool stated by `tools`, makes the next `mcpp build -v` decline the fast path with "a program of the toolchain named by path changed".
6. `--managed-only` and `MCPP_MANAGED_ONLY=1` refuse a build that uses such a toolchain.
7. `mcpp.lock` records the toolchain as `local` (stated in the specification; the `lock-local` case checks it).

## Branches under test

The references are in [`refs.env`](refs.env), so the diff of a pull request shows what it measures.

| Variable | Value | What it is |
| --- | --- | --- |
| `MCPP_REF` | `feat/build-sources` | branch of `mcpp-community/mcpp` (pull request #758, version 2026.10.1.3); built from source in every job |
| `PLUGINS_REF` | `feat/0.19.0-tool-sources` | branch of `mcpp-community/mcpp-plugins` (version 0.19.0); provides `mcpp.plugins.toolchain` |
| `MCPP_BOOTSTRAP` | `2026.10.1.2` | released mcpp that builds the engine under test |

## Method

Each job installs the released mcpp `MCPP_BOOTSTRAP` from its GitHub release asset, sets `MCPP_HOME` inside the workspace (kept by `actions/cache`), and builds `mcpp-community/mcpp` at `MCPP_REF` with it. The built binary is `$MCPP`; the job fails unless `$MCPP --version` is `mcpp 2026.10.1.3`. The plugins repository is cloned at `PLUGINS_REF` for the cases that need `mcpp.plugins.toolchain`.

**The toolchain under test is the managed LLVM payload without the files mcpp generates.** `scripts/make-tree.sh` locates the installed LLVM payload (`$MCPP_HOME/registry/data/xpkgs/xim-x-llvm/<version>`; on Linux it installs `llvm@22.1.8` first, because mcpp builds itself with gcc there) and makes a directory whose `bin/` holds a symlink to every program of the payload's `bin/` except the `*.cfg` files, plus symlinks for `include`, `lib`, `share` and `libexec`. That tree is what a hand-extracted LLVM release looks like, and it is what the cases name by path. The job prints the tree's path and the driver's version.

Every case is a script in `cases/`, run by `scripts/case.sh <case>` under `shell: bash`, so one script serves every platform. A case prints its commands, their complete output and one `VERDICT` line (`PASS`, `FAIL`, `SKIP` with the reason, or `KNOWN-RED` with the tracked issue); the verdicts are repeated in the job summary. Messages are asserted on uncoloured text (`NO_COLOR=1`).

| Case | What it asserts |
| --- | --- |
| `path-llvm` | `default = { path = "<tree>" }`; a C++23 program that includes `<vector>` and uses `std::format` builds and runs; the `Using toolchain` line carries `[custom · mcpp.toml:<line>]`; `Finished` ends in `custom: toolchain`; `resolution.json` records `toolchain.build` with `class: custom`; `mcpp why toolchain` prints `source:`; no `*.cfg` file was created under the tree |
| `env-path` | the same project with no `[toolchain]` table and `MCPP_TOOLCHAIN=path:<tree>`; the tag is `[custom · env MCPP_TOOLCHAIN]` |
| `launcher-and-ld` | `launcher = "/usr/bin/env"` (a pass-through, since ccache may be absent) and `tools = { ld = "<wrapper that execs the tree's lld>" }`; `build.ninja` has the launcher in front of the compiler and `--ld-path=` naming the wrapper; the program runs |
| `fast-path` | two unchanged builds do not print "fast-path: build declined" under `-v`; after touching the linker wrapper the next `-v` build prints "a program of the toolchain named by path changed"; the same after touching the driver |
| `toolchain-phase` | `default = { configure = "build.mcpp" }` with `bootstrap = "llvm@<payload version>"`; `build.mcpp` states the tree with `configure`, `layout` and `use`; the output has the `Bootstrap` line and `[program · build.mcpp:<line>]`; the build phase of the same program ran; the program runs |
| `phase-refuses-a-flag` | the same project whose toolchain phase also calls `mcpp::cxxflag("-DX")` is refused, and the message names `mcpp:cxxflag=` |
| `managed-only` | the `path-llvm` project with `--managed-only` (and with `MCPP_MANAGED_ONLY=1`) is refused, and the message names the toolchain |
| `lock-local` | `mcpp.lock`, or the message of a build on a machine without the tree, records the toolchain as `local`; when it does not, the case records what the lock does carry |

A case that the platform cannot support is skipped with the reason printed and recorded.

### The xcode-27 job

`xcode-27` is the preview label for macOS 27 with Xcode 27 (there is no `macos-27` label). The job first asserts that `sw_vers -productVersion` has major version 27 and prints `ImageVersion`, `xcodebuild -version` and `xcrun --show-sdk-path`. It runs `path-llvm` and `toolchain-phase`.

The SDK of that image lists the architecture `arm64e.x1` in its text stubs, which the `ld64.lld` of LLVM 22.x and 23.1.2 cannot read (mcpp-community/mcpp#669; upstream fix llvm/llvm-project#222721). The job therefore chooses its toolchain tree as follows.

- If a release of `speak-agent/llvm-macos27-lab` has an asset named `llvm-23.1.2-x1-macos-arm64.tar.xz`, that asset is the toolchain tree. Its lld carries the fix.
- Otherwise the tree is built from the managed payload exactly as on the other platforms, and the link is expected to fail with `arm64e.x1`. That outcome is the expected state of mcpp-community/mcpp#669. It is reported as `KNOWN-RED` and is not a failure of the feature under test. A failure whose output does not contain `arm64e.x1` is still a `FAIL`.

The job runs the engine binary built by the `macos-15` job, because building one on `xcode-27` fails at its first link for the same reason. `toolchain-phase` links its build program with the managed bootstrap toolchain (`bootstrap` accepts a managed spec only), so it meets the same lld whichever tree the phase states.

## Results

No run is recorded yet.

| Case | linux | macos-15 | xcode-27 |
| --- | --- | --- | --- |

## Re-running

- Pull requests, pushes to `main` and manual dispatches run `.github/workflows/lab.yml`. A newer run of the same ref cancels the older one.
- `gh workflow run lab.yml -R speak-agent/mcpp-toolchain-lab --ref <branch>` starts a run by hand.
- To measure another build of the engine or of the plugins, change `refs.env` in a pull request. `ENGINE_VERSION` in the workflow is the version the engine built from `MCPP_REF` must print.
- To run a case on a machine that has the three inputs (an engine as `$MCPP`, a managed LLVM payload in `$MCPP_HOME`, a clone of mcpp-plugins):

  ```sh
  export MCPP=/path/to/mcpp MCPP_HOME=$HOME/.mcpp PLUGINS_REF=feat/0.19.0-tool-sources
  export LAB_ENV_FILE=$PWD/lab.env
  bash scripts/clone-plugins.sh && bash scripts/make-tree.sh   # print the clone, the tree and the driver
  . ./lab.env                                                  # LAB_PLUGINS, LAB_TREE, LAB_PAYLOAD, LAB_LLVM_VERSION
  bash scripts/case.sh path-llvm
  ```

## License

Apache-2.0. See [LICENSE](LICENSE).
