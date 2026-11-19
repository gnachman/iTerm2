# Performance, memory, and hot paths

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

## 1. Performance and memory

Hot paths are deferred (section 2), but ordinary code can still regress
through bridging and allocation. Rules for all ported code:

- **Bridging at the boundary is the main cost in a mixed codebase.** A Swift
  method that takes `[String]` and is called from Objective-C converts the
  whole array on every call. A Swift `String` made from an `NSString` may copy.
  For any `@objc` method the dossier marks as frequently called, keep the `NS`
  types in the signature in stage one and use them directly inside.
- No `Any`, no existential protocol types, and no closures allocated per
  iteration in loops over cells, characters, lines, or tokens.
- Prefer `final` on classes and members that nothing overrides, once the
  census confirms it, so calls are direct. Stage one cannot always do this
  (xib and Objective-C subclassing), so record it for stage two.
- Avoid accidental copies of arrays held in class properties: mutate in place
  rather than read, modify, and write back, and do not hold a second reference
  across a mutation.
- Keep whole-module optimization and `-O` for release configurations.
- Release builds keep Swift's safety checks. No `-Ounchecked`, and no setting
  that disables safety checks, in any configuration. They are what makes an
  out-of-bounds access a clean crash instead of memory corruption.
- The arithmetic helpers ([translation-rules.md §1](translation-rules.md)) cost a few instructions on the path
  where nothing overflows. The performance baselines show whether that
  matters anywhere outside hot paths.
- Do not add work to `deinit` or to property observers that was not in the
  Objective-C.

Measurement:

- A port of any unit the dossier marks as warm (called per line, per update,
  per keystroke) runs the perf harness (section 3) before and after. A
  regression beyond noise blocks the commit.
- Memory is checked with the scripted workload (section 3): resident size and
  allocation count. Swift value types boxed into `Any` or into existentials, and
  bridged collections kept alive alongside their originals, are the usual
  causes of growth.
- Build time matters too. One Swift module compiled whole now holds about 940
  files and will roughly double. As clusters of leaf code become free of
  Objective-C dependents, they should move into separate modules. That also
  makes dependency cycles a compile error. The first such split is a decision
  for the owner once the leaf tier is under way.

## 2. Hot paths

Left until everything else is done, per the owner. For reference, the areas
are the parser and terminal (`sources/VT100`), screen state and grid
(`sources/VT100Screen`), `sources/LineBuffer`, `sources/MetalRenderer`, text
drawing in `sources/Drawing`, and the per-frame parts of `PTYTextView`.

Until then:

- A unit whose dossier finds a per-character, per-cell, per-token, or per-frame
  method is moved to the hot-path list and skipped.
- Ported code that calls into hot paths keeps calling the C and Objective-C
  entry points unchanged.
- The shared C types these paths define (`screen_char_t`, the grid coordinate
  structs) stay in C headers.

When the time comes, each hot path gets its own plan with benchmarks written
first, and the option of staying in C with bounds-checking compiler support
instead of moving to Swift is evaluated on its merits.

## 3. The perf harness

`tools/swift_migration/perf_baseline.py` runs the scenarios and writes a
result file; `tools/swift_migration/perf_compare.py` compares two result
files. Their `--help` is the manual; `perf_baseline.py list` prints the
scenarios. Built on 2026-11-20. **No baseline numbers have been taken yet**:
that needs a quiet machine (below).

**Configuration.** Measured in `Deployment`, the release configuration
(whole-module, `-O`, no address sanitizer), unsigned, `arm64`, into
`Build/Deployment`. It is what ships, and the `PerformanceTests` scheme
already tests in it. The runner calls `xcodebuild build-for-testing` with the
Makefile's flags rather than `make Deployment`, which would also run
`tools/extract_strings.sh` and rewrite the tracked string catalog.

**Scenarios.** In-process, in the `PerformanceTests` target
(`PerformanceTests/MigrationBaselineTests.swift` and the two existing tests
in `PerformanceTests.swift`), each through `xcodebuild test-without-building`
with the test host started with `-suite <checkout directory name>`. The
target had stopped compiling when this was built: its fake screen delegate
had fallen behind `VT100ScreenDelegate`, and in a configuration built without
testability a Swift class outside the module cannot declare that conformance
at all, because some of its methods take classes internal to
`iTerm2SharedARC`. The fake is now a copy of the one in `ModernTests` whose
conformance is added at run time and whose selectors are checked by every
test that uses it; when the protocol changes, copy it again:

| Scenario | What it measures |
|---|---|
| `parse.mixed_1mb` | `VT100Parser` alone on 1 MB of mixed output: ASCII, 256-color and 24-bit SGR, CJK and emoji, cursor moves |
| `screen.parse_execute_mixed_1mb` | The same bytes parsed and executed on a 120x50 `VT100Screen` whose 10,000-line scrollback is already full |
| `screen.gang_fast_path`, `screen.char_at_a_time` | The existing `PerformanceTests`: 10,000 ASCII lines appended through the gang path and a string at a time |
| `draw.attributed_strings_mono`, `_truecolor`, `_truecolor_ligatures` | The per-row attributed string build of text drawing (`iTermAttributedStringBuilderBenchmark`), 250x80, time per frame |
| `memory.scrollback_fill_20k` | The scripted memory workload: a 20,000-line scrollback filled with three passes of the 1 MB stream, each 64 KB chunk in its own autorelease pool as in the app, then released. XCTest's peak physical memory during the fill, the net growth in live malloc blocks and bytes over a sample, footprint growth, XCTest's "memory physical", and the test host's peak footprint. Only the peak is an effective gate today (below) |

In the app, through `tools/perf/run_stress_test.sh` against
`Build/Deployment/iTerm2.app`, five runs of 20 seconds each: modes `normal`,
`buffer`, `clearcodes` and `flood` with one tab, `normal` with ten tabs, and
`htop` unthrottled. Each gives the script's iterations per second, and the
app's peak and steady-state resident size, sampled once a second by the
runner. Latency is not measured: the script's latency figures come only from
an instrumented build, which this tree does not have. Launch time is not
measured: no document asks for it.

Allocation count means live malloc blocks (`malloc_zone_statistics`): macOS
offers no cheap count of all allocations made.

What each memory metric can detect, from the spreads of the first runs (busy
machine, five samples):

- `memory_peak_physical`, XCTest's peak physical memory during the fill, 0.1%
  spread: the usable memory gate.
- `process_peak_footprint`: one sample per run, so always inconclusive.
- `live_malloc_blocks`, 17% spread: it would always be inconclusive, so **the
  allocation count is not effectively compared today**.
- `live_malloc_bytes`, 0.0% spread, but a net change over a sample: a uniform
  regression in what each screen allocates would be largely cancelled by the
  previous sample's screen giving back as much.
- `footprint_growth` and XCTest's `memory_physical`, about 150 to 200%
  spread: no signal.

All but the first two are therefore marked informational: recorded, shown,
never compared. The explanation offered for the noise and the cancellation,
that one sample's screen is freed lazily on its own queues while the next
sample runs, is a hypothesis, not verified.

Open point: make the live allocation metrics deterministic, by measuring in
a fresh process per sample or by draining the previous screen before
sampling, and then compare them.

**Result file.** JSON, schema `iterm2-migration-perf/1`: the label (`baseline`
or `not a baseline: <why>`), the commit and whether the tree had uncommitted
changes outside `docs/`, the configuration and architecture, the machine
(model, chip, cores, memory, macOS and Xcode versions; never the host or
user name), the machine's state before and after with the quiet verdict and
its reasons, and per scenario its status and, per metric, the unit, which
direction is better, every sample and a summary (median, minimum, maximum,
MAD, robust relative spread). Results go to `tmp/perf-baseline/results/` by
default. Where the baseline file is kept once taken is for the owner to
decide.

**Quiet machine.** A run is labeled a baseline only if, before the first
scenario and after the last: the 1- and 5-minute load averages are at most
a quarter of the logical CPUs; `memory_pressure` reports at least 30 percent
free; no `xcodebuild`, `swift-frontend`, `clang`, `ld` or similar build
process is running; the Mac is on AC power, not in Low Power mode, and not
thermally limited; and the tree has no uncommitted changes outside `docs/`.
A changed submodule pointer counts as a change, because the shell integration
submodule is copied into the app bundle. `--baseline` on a busy machine or a
dirty tree is refused before anything is built, unless `--force` is given,
and the result then says `not a baseline: ...`. A run in which any scenario
failed is labeled `not a baseline: scenario failed: <names>`; skipped
scenarios do not affect the label. Swap in use is recorded, not gated on;
the paths that made a tree dirty are recorded in the result. If the only
change is an unwanted submodule pointer, `git submodule update` restores it;
otherwise take the baseline in a clean checkout.

**Comparison.** `perf_compare.py BASELINE CANDIDATE` gives a verdict per
scenario and metric. The threshold is a proposal awaiting the owner, since
section 1 says "beyond noise" without defining noise: a regression is a
median worse by more than max(5%, 3 x noise), noise being the larger robust
relative spread (1.4826 x MAD / median) of the two runs; fewer than five
samples or more than 10% noise is inconclusive. Every scenario named in
either file gets at least one row. A scenario that failed in the candidate
(crashed, timed out, its test failed, or any status other than ok or
skipped) gives `failed in candidate` with the recorded reason, whatever the
reference holds; if the reference failed too, the note says `also failed in
reference`, so a before and after with the same failure does not read as
clean. A metric an otherwise successful scenario no longer reports gives
`missing in candidate`. Both block like a regression (exit 1). A scenario
the candidate skipped (the app scenarios are skipped while any iTerm2 runs)
or did not select is not compared, also when the reference skipped it too:
its rows say `skipped in candidate` or `not run in candidate`. A scenario the
candidate ran but the reference skipped, failed or did not run gives `no
reference result`. Warnings name every scenario in either of those groups,
and the exit status is unchanged, so a caller that relies on a scenario must
make sure it ran in both. Informational metrics are shown and never
compared. It refuses (exit 2) to compare across configurations or machines,
or against a result not labeled a baseline, unless told to
(`--allow-different-machine`, `--allow-non-baseline`); different Xcode or
macOS versions give a warning. For the before and after of a port, run both
on the same machine in one sitting and pass `--allow-non-baseline`.

**Taking the baseline.** On the owner's machine, quiet: no agents or builds
running, on AC power, and with the owner's own iTerm2 quit, because
`run_stress_test.sh` refuses to start while any process named iTerm2 is
running (its AppleScript addresses the app by name). From Terminal.app, in a
checkout at the commit to measure with a clean tree (`docs/` aside, and
including the submodule pointers: a checkout whose
`submodules/iTerm2-shell-integration` pointer is modified is refused):

    python3 -B tools/swift_migration/perf_baseline.py state
    python3 -B tools/swift_migration/perf_baseline.py run --baseline

The first command should report `"quiet": true`. The second builds
`Deployment` (about 20 to 40 minutes from clean on a quiet machine, an
estimate), waits up to ten minutes for the load of the build to settle,
then runs the in-process scenarios (about 5 minutes) and the app scenarios
(about 25 minutes, during which test windows open and come to the front;
leave the machine alone). Expect about an hour in all. The app scenarios
use the isolated suite `com.iterm2.stress-test`, whose Application Support
folder the script deletes before each run. To take only the in-process part,
with the owner's iTerm2 still running, add `--scenarios 'parse.*,screen.*,draw.*,memory.*'`;
after a build has been done once, `--skip-build` saves the build.
