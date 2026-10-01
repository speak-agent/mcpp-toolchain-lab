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
7. A machine that does not have the tree is refused where the declaration is read, naming the tree, and is not built with another toolchain. `mcpp.lock` holds the result of dependency resolution and no toolchain; the engine states so since its commit 11431544 (an earlier statement said the lock records the toolchain as `local`; the `lock-local` case first expected that and was restated, see the findings).

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

Every case is a script in `cases/`, run by `scripts/case.sh <case>` under `shell: bash`, so one script serves every platform. A case prints its commands, their complete output and one `VERDICT` line (`PASS`, `FAIL`, `SKIP` with the reason, or `KNOWN-RED` with the tracked issue and the mark that the failing output carries); the verdicts are repeated in the job summary. Messages are asserted on uncoloured text (`NO_COLOR=1`).

| Case | What it asserts |
| --- | --- |
| `path-llvm` | `default = { path = "<tree>" }`; a C++23 program that includes `<vector>` and uses `std::format` builds and runs; the `Using toolchain` line carries `[custom · mcpp.toml:<line>]`; `Finished` ends in `custom: toolchain`; `resolution.json` records `toolchain.build` with `class: custom`; `mcpp why toolchain` prints `source:`; no `*.cfg` file was created under the tree |
| `env-path` | the same project with no `[toolchain]` table and `MCPP_TOOLCHAIN=path:<tree>`; the tag is `[custom · env MCPP_TOOLCHAIN]` |
| `launcher-and-ld` | `launcher = "/usr/bin/env"` (a pass-through, since ccache may be absent) and `tools = { ld = "<wrapper that execs the tree's lld>" }`; `build.ninja` has the launcher in front of the compiler and `--ld-path=` naming the wrapper; the wrapper ran during the link; the program runs |
| `fast-path` | two unchanged builds do not print "fast-path: build declined" under `-v`; after touching the linker wrapper the next `-v` build prints "a program of the toolchain named by path changed"; the same after touching the driver |
| `toolchain-phase` | `default = { configure = "build.mcpp" }` with `bootstrap = "llvm@<payload version>"`; `build.mcpp` states the tree with `configure`, `layout` and `use`; the output has the `Bootstrap` line and `[program · build.mcpp:<line>]`; the build phase of the same program ran; the program runs |
| `phase-refuses-a-flag` | the same project whose toolchain phase also calls `mcpp::cxxflag("-DX")` is refused, and the message names `mcpp:cxxflag=` |
| `managed-only` | the `path-llvm` project with `--managed-only` (and with `MCPP_MANAGED_ONLY=1`) is refused, and the message names the toolchain |
| `lock-local` | `mcpp.lock` is written and holds the resolved dependency (a build whose graph has no index package writes none, so the project has one); the build record holds the toolchain as `class: custom`; a build on a machine without the tree is refused naming the tree and "no C++ driver in bin/". What the lock and the record carry is printed |
| `toolchain-phase-lab-lld` | `xcode-27` only, and only when the tree is the lab asset: the `toolchain-phase` case with the lld files of the managed payload replaced by the lab's lld for the length of the case (the originals are put back) |

A case that the platform cannot support is skipped with the reason printed and recorded.

### The xcode-27 job

`xcode-27` is the preview label for macOS 27 with Xcode 27 (there is no `macos-27` label). The job first asserts that `sw_vers -productVersion` has major version 27 and prints `ImageVersion`, `xcodebuild -version` and `xcrun --show-sdk-path`. It runs `path-llvm` and `toolchain-phase`.

The SDK of that image lists the architecture `arm64e.x1` in its text stubs, which the `ld64.lld` of LLVM 22.x and 23.1.2 cannot read (mcpp-community/mcpp#669; upstream fix llvm/llvm-project#222721). The job therefore chooses its toolchain tree as follows.

- If a release of `speak-agent/llvm-macos27-lab` has an asset named `llvm-23.1.2-x1-macos-arm64.tar.xz`, that asset is the toolchain tree. It is the official LLVM 23.1.2 package, trimmed, with an lld built from `release/23.x` at `21ef2ddb8060`, which carries the fix. The asset is extracted and used as it is, so it is a real extracted tree with no symlinks and no `*.cfg` files.
- Otherwise the tree is built from the managed payload exactly as on the other platforms, and the link is expected to fail with `arm64e.x1`. That outcome is the expected state of mcpp-community/mcpp#669. It is reported as `KNOWN-RED` and is not a failure of the feature under test. A failure whose output does not contain `arm64e.x1` is still a `FAIL`.

The job runs the engine binary built by the `macos-15` job, because building one on `xcode-27` fails at its first link for the same reason.

`toolchain-phase` links its build program with the bootstrap toolchain, and `bootstrap` accepts a managed spec only. The build program is therefore linked by the managed LLVM's lld, whichever tree the toolchain phase states, and on this image it meets the SDK that lld cannot read before the stated toolchain is ever used. The case is reported `KNOWN-RED` (#669) there. `toolchain-phase-lab-lld` removes that one cause, by putting the lab's lld in place of the managed payload's for the length of the case, and shows the toolchain phase working on the image.

## Results

Run [36889621198](https://github.com/speak-agent/mcpp-toolchain-lab/actions/runs/36889621198), a manual dispatch on the branch of pull request #1 (conclusion `success`). Every run of the pull request is listed under its checks; the earlier ones, at earlier engine commits, are the evidence for findings 1 and 2.

| Input | Value |
| --- | --- |
| engine | `mcpp-community/mcpp` `feat/build-sources` at `cb918615e81bd297b1997f0f8f29e32c39db8846`; `mcpp --version` prints `mcpp 2026.10.1.3` |
| plugins | `mcpp-community/mcpp-plugins` `feat/0.19.0-tool-sources` at `789a0bb36c10e3b9a41c15de899cb64ed5024e10`, package version 0.19.0 |
| bootstrap | released mcpp 2026.10.1.2 |
| `linux` | `ubuntu-24.04`, image 20260927.320.1; tree from the managed `llvm@22.1.8` payload (clang 22.1.8) |
| `macos-15` | `macos-15-arm64`, image 20260907.0337.1 (Xcode 16.4); tree from the managed `llvm@22.1.8` payload |
| `xcode-27` | `xcode-27-arm64`, image 20260928.0222.1; macOS 27.0 (26A428), Xcode 27.0 (27A266a), SDK 27.0 (`libSystem.tbd` lists `arm64e.x1`); tree is the release asset `llvm-23.1.2-x1-macos-arm64.tar.xz` of `speak-agent/llvm-macos27-lab` release `toolchain-21ef2ddb8060` (clang 23.1.2, lld 23.1.3 at `21ef2ddb8060`) |

| Case | linux | macos-15 | xcode-27 |
| --- | --- | --- | --- |
| `path-llvm` | PASS | PASS | PASS (lab tree) |
| `env-path` | PASS | PASS | not run |
| `launcher-and-ld` | PASS | PASS (finding 1, fixed) | not run |
| `fast-path` | PASS | PASS | not run |
| `toolchain-phase` | PASS | PASS | KNOWN-RED (#669, `arm64e.x1`; finding 3) |
| `toolchain-phase-lab-lld` | not run | not run | PASS |
| `phase-refuses-a-flag` | PASS | PASS | not run |
| `managed-only` | PASS | PASS | not run |
| `lock-local` | PASS (restated, finding 2) | PASS (restated, finding 2) | not run |

Nothing was skipped. `not run` marks a case that is not part of that job: `xcode-27` runs `path-llvm` and `toolchain-phase` (and `toolchain-phase-lab-lld`), and `toolchain-phase-lab-lld` needs the lab tree.

### Findings

1. **`tools = { ld = ... }` was ignored on macOS (an engine defect, fixed in engine commit cb918615).** The project is
   `default = { path = "<tree>", launcher = "/usr/bin/env", tools = { ld = "<wrapper that execs ld64.lld>" } }`. Before the fix `mcpp build` exited 0 and reported the toolchain, and `build.ninja` had the launcher (`cxx = /usr/bin/env <tree>/bin/clang++`), but the link options were

   ```
   ldflags   = -isysroot /Applications/Xcode_16.4.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -fuse-ld=lld -mmacosx-version-min=14.0
   ```

   with no `--ld-path=`, and the wrapper, which appends a line to a file each time it runs, never ran. On Linux the same case had `--ld-path=<wrapper>` in `ldflags` and the wrapper ran. The cause was in `src/build/flags.cppm`: the `--ld-path` was appended inside the Linux clang branch, the only one that consumed `link_toolchain_flags`, so the stated linker entered the fingerprint (the `fast-path` case passed on macOS: touching the wrapper declined the fast path) and took no part in the link, and the engine printed no diagnostic. The `build.ninja` evidence was seen at engine commits 11431544, 23c5843f, eb386f65, 7819a28c and 77b632fd (runs 36879774963 to 36887677223); the wrapper's own record of running was added to the case later and is from 77b632fd, run 36887677223, which failed with `the wrapper ran during the link: no`. At cb918615 the link options end in `--ld-path=<wrapper>` and the wrapper runs, on `macos-15` (run 36889621198). The engine's own end-to-end test for this (e2e 875) asserts `--ld-path` but skips on a host that has no LLVM payload installed, which is what the macOS CI of the engine is, so it never ran where the defect was; this lab runs the case there. A gcc toolchain that states `ld` is refused by the engine from cb918615, because gcc selects a linker by the name `ld` in a `-B` directory; the lab has no gcc case.
2. **`mcpp.lock` does not record the toolchain.** The case first expected a `local` entry in `mcpp.lock`, or the word in the message of a build without the tree. A build with a path-named toolchain and the dependency `cmdline = "0.0.2"` writes a lock that holds only `[package."cmdline"]` (`namespace = "mcpplibs"`, `version = "0.0.2"`, `source = "index+mcpplibs@0.0.2"`, `hash = "fnv1a:f5015fdab7dc3807"`), and `resolution.json` holds `sources[]` with `{subject: "toolchain.build", class: "custom", value: <tree>}`. With the tree moved away, `mcpp build` exits 2 with

   ```
   error: [toolchain].linux = 'path:<tree>': '<tree>' has no C++ driver in bin/ (a `clang++` or a `g++`, optionally with a prefix); a toolchain named by path keeps its drivers in `<path>/bin`
   ```

   which does not say `local`. The engine's commit 11431544 states that this is the design (a toolchain is not a resolved dependency), so the case was restated to assert the refusal. The first three runs of this pull request (36879774963, 36881286614, 36882750682), which still expected `local`, failed this case on both platforms. The refusal names `[toolchain].linux` where the manifest wrote `default`.
3. **`bootstrap` accepts a managed spec only**, so on a host whose SDK the managed lld cannot read, the toolchain phase cannot start even when the toolchain it states can link. On `xcode-27` the `toolchain-phase` case fails while compiling `build.mcpp`, before the stated tree is used:

   ```
   error: the root build program's toolchain phase: build.mcpp failed to compile (exit 1):
   ld64.lld: error: could not load TAPI file at /Applications/Xcode_27.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/libc++.tbd: malformed file
   .../libc++.tbd:4:54: error: unknown architecture
   ```

   (`libSystem.tbd:4:20` as well.) With the lab's lld in the managed payload (`toolchain-phase-lab-lld`), the same build program compiles, `Bootstrap llvm@22.1.8` is reported, `Using toolchain clang 23.1.2 ← <lab tree>  [program · build.mcpp:9]` follows, the build phase runs and the program runs. This is the expected state of mcpp-community/mcpp#669 and not a defect of the feature.
4. **A tree of symlinks is not a tree without a cfg.** The tree made from the payload has no `*.cfg` file, but each driver is a symlink into the payload, so clang run by hand resolves its own path to the payload and reads the payload's cfg (`InstalledDir: <payload>/bin`, `Configuration file: <payload>/bin/clang++.cfg`). On Linux mcpp drives the compiler with `--no-default-config` and states every path itself, and the `path-llvm` case asserts that nothing was written, but the case does not show that a driver without a cfg beside it works. The `xcode-27` tree, which is a real extracted release, has none and builds and runs.

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
