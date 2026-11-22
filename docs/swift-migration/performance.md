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
  regression beyond noise blocks the commit. Time and rate metrics are
  estimated by their best sample (owner, 2026-11-22); the thresholds, and
  the median for memory and counts, are proposals (section 3,
  **Comparison**).
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
scenarios. Built on 2026-11-20.

**The baseline** was taken on 2026-11-22 on the app sources of "Port
iTermColorSuggester to Swift" with one header annotation added
(`-screenRestoreState:` made nullable, which changes no generated code),
labeled `baseline` by the runner: Mac16,6, Apple M4 Max, macOS 27.0 (26A428), Xcode 27.0 Build version 27A266a; load average
before [1.77, 3.78, 4.96], after [2.2, 2.42, 3.11], settled at once. The owner had quit his other programs,
his own iTerm2 among them, and no agent or build ran beside it. The result
file is `tmp/perf-baseline/results/baseline-2026-11-22.json` in the main
checkout, which git ignores: where it is kept for good is the owner's
decision (owner-queue.md Q23 item 3), and until then this table is the
committed record. Best is the fastest sample: the minimum where lower is
better, the maximum for the iteration rates. The bold figure in each row is
the one `perf_compare.py` compares (below, **Comparison**): Best for time
and rate metrics (decided), Median for memory and counts (proposed); rows
with neither in bold are informational. `process_peak_footprint` has one
sample per run, so its comparison is always inconclusive and its median is
not in bold.

| Scenario | Metric | Median | Best | Minimum | Maximum | Samples | Spread |
|---|---|---|---|---|---|---|---|
| `parse.mixed_1mb` | `time` | 0.0240895 s | **0.0226329 s** | 0.0226329 | 0.0252083 | 10 | 6.0% |
| `screen.parse_execute_mixed_1mb` | `time` | 0.0553406 s | **0.053493 s** | 0.053493 | 0.057615 | 10 | 2.6% |
| `screen.gang_fast_path` | `time` | 0.00464904 s | **0.00449471 s** | 0.00449471 | 0.00499629 | 10 | 4.8% |
| `screen.char_at_a_time` | `time` | 0.0306154 s | **0.0299207 s** | 0.0299207 | 0.0347527 | 10 | 1.5% |
| `draw.attributed_strings_mono` | `time_per_frame` | 3.02222 ms | **2.93073 ms** | 2.93073 | 3.1634 | 10 | 1.4% |
| `draw.attributed_strings_truecolor` | `time_per_frame` | 40.6209 ms | **39.5833 ms** | 39.5833 | 42.7131 | 10 | 2.3% |
| `draw.attributed_strings_truecolor_ligatures` | `time_per_frame` | 63.4905 ms | **61.9881 ms** | 61.9881 | 67.157 | 10 | 1.6% |
| `memory.scrollback_fill_20k` | `clock_monotonic_time` | 0.161565 s | **0.158502 s** | 0.158502 | 0.170952 | 10 | 2.8% |
| `memory.scrollback_fill_20k` | `footprint_growth` | 16 kB | -48 | -48 | 48 | 10 | 148.3% |
| `memory.scrollback_fill_20k` | `live_malloc_blocks` | 2028.5 count | 1517 | 1517 | 3036 | 10 | 19.2% |
| `memory.scrollback_fill_20k` | `live_malloc_bytes` | 4730.67 kB | 4716.59 | 4716.59 | 4755.59 | 10 | 0.3% |
| `memory.scrollback_fill_20k` | `memory_peak_physical` | **48817.2 kB** | 48743.5 | 48743.5 | 48891 | 10 | 0.1% |
| `memory.scrollback_fill_20k` | `memory_physical` | 8.192 kB | -49.152 | -49.152 | 49.152 | 10 | 148.3% |
| `memory.scrollback_fill_20k` | `process_peak_footprint` | 69217.1 kB | 69217.1 | 69217.1 | 69217.1 | 1 | 0.0% |
| `app.stress_normal_1tab` | `iterations_per_sec` | 1119 iterations/s | **1890 iterations/s** | 1059 | 1890 | 5 | 7.9% |
| `app.stress_normal_1tab` | `rss_peak` | **336960 kB** | 293104 | 293104 | 344480 | 5 | 2.9% |
| `app.stress_normal_1tab` | `rss_steady` | **311920 kB** | 275528 | 275528 | 327200 | 5 | 7.0% |
| `app.stress_buffer_1tab` | `iterations_per_sec` | 456 iterations/s | **471 iterations/s** | 426 | 471 | 5 | 4.9% |
| `app.stress_buffer_1tab` | `rss_peak` | **286960 kB** | 285184 | 285184 | 290144 | 5 | 0.9% |
| `app.stress_buffer_1tab` | `rss_steady` | **262848 kB** | 260296 | 260296 | 265920 | 5 | 0.8% |
| `app.stress_clearcodes_1tab` | `iterations_per_sec` | 851 iterations/s | **1177 iterations/s** | 752 | 1177 | 5 | 15.2% |
| `app.stress_clearcodes_1tab` | `rss_peak` | **266688 kB** | 264544 | 264544 | 268976 | 5 | 0.5% |
| `app.stress_clearcodes_1tab` | `rss_steady` | **242544 kB** | 240704 | 240704 | 243744 | 5 | 0.7% |
| `app.stress_flood_1tab` | `rss_peak` | **309024 kB** | 300048 | 300048 | 317488 | 5 | 1.6% |
| `app.stress_flood_1tab` | `rss_steady` | **285136 kB** | 276032 | 276032 | 293408 | 5 | 2.2% |
| `app.stress_normal_10tabs` | `iterations_per_sec` | 959 iterations/s | **2340 iterations/s** | 953 | 2340 | 5 | 0.9% |
| `app.stress_normal_10tabs` | `rss_peak` | **476336 kB** | 449648 | 449648 | 507040 | 5 | 3.8% |
| `app.stress_normal_10tabs` | `rss_steady` | **438784 kB** | 410112 | 410112 | 453296 | 5 | 4.9% |
| `app.stress_htop_unthrottled_1tab` | `iterations_per_sec` | 349 iterations/s | **359 iterations/s** | 324 | 359 | 5 | 4.2% |
| `app.stress_htop_unthrottled_1tab` | `rss_peak` | **294416 kB** | 288640 | 288640 | 311280 | 5 | 2.9% |
| `app.stress_htop_unthrottled_1tab` | `rss_steady` | **270496 kB** | 264520 | 264520 | 287344 | 5 | 3.3% |

Read with care:

- The app scenarios' iteration rates are not steady from run to run in two
  of the six. `app.stress_normal_10tabs` gave 2056, 953, 2340, 959 and 953
  iterations per second: two levels, and the spread figure (0.9%), which is
  built on the median's neighbours, does not show it.
  `app.stress_normal_1tab` gave 1890, 1119, 1323, 1059 and 1084, and
  `app.stress_clearcodes_1tab` 870, 752, 1177, 764 and 851. Since the
  owner's decision of 2026-11-22 rates are estimated by their best sample,
  and under the proposed threshold (below, **Comparison**) a candidate
  whose best is more than 5% below the baseline's (2340, 1890 and 1177
  here) is a regression however its median moved. What that protects
  against: a few slow runs among otherwise normal ones, from a busy moment
  or the slow level, faking a change, since one fast run on each side is
  enough. What it does not protect against:
  - A clean candidate that never comes within 5% of the baseline's best.
    In each of these three rates only one of the five baseline samples is
    within 5% of the best (2056 is 12% below 2340). Assuming the level of
    each run is random and independent, with the chance of a fast run
    estimated from those five runs as 1 in 5, a five-run candidate misses
    with probability 0.8 to the fifth power, about 0.33, for each of the
    three rates, and a clean candidate shows a false regression on at
    least one of them about 70% of the time (1 - 0.672 cubed; the buffer
    and htop rates, with three of five samples within 5%, add about 1%
    each). A five-sample estimate of that chance is itself rough. A rate
    regression whose candidate best sits near the baseline's slow level
    (about 950, 1100 and 800) should be rerun before it is believed.
  - A fast outlier. One fast candidate run reads as an improvement and
    hides a real regression in the rest, and a fast outlier in the
    baseline makes every later candidate look slower. "These three rates"
    may be too narrow: in `busy-after-2026-11-22.json` (not a baseline,
    so weaker evidence) `app.stress_buffer_1tab` has a sample of 1027
    against a baseline best of 471, `app.stress_htop_unthrottled_1tab`
    567 against 359, and `app.stress_normal_1tab` 2488 against 1890.
  - Code that slows only the typical run while one run stays fast, since
    the median is reported beside the best but not judged.

  The cause of the two levels is not known. Two short runs
  of `app.stress_normal_1tab` earlier the same day, ten seconds each, with
  the owner's iTerm2 running in front, gave 9,160 and 9,927 iterations per
  second, seven times these; whether the window being in front, the run's
  length or something else explains it was not investigated.
- `memory_physical` and `footprint_growth` of `memory.scrollback_fill_20k`
  are a few kilobytes with a spread over 100%: noise around zero, not a
  measure. `memory_peak_physical` and `live_malloc_bytes` are the steady
  ones.
- Best against best does not protect against a run made on a busy
  machine, and that is not limited to the app rates: a busy machine slows
  the fastest run too, not only the typical one. Three other result files
  of 2026-11-22 in `tmp/perf-baseline/results/` hold app and test code
  identical to the baseline's (only tool commits differ). Compared with
  `perf_compare.py --allow-non-baseline`, each shows false regressions
  over the proposed fixed 5% on in-process time metrics with 10 samples a
  side:
  - `forced-2026-11-22.json`, load average about 8 (before [4.87, 7.77,
    8.39]) with the owner's programs running: `screen.gang_fast_path`
    7.77%, `draw.attributed_strings_truecolor` 5.74%,
    `draw.attributed_strings_truecolor_ligatures` 6.75%.
  - `collided-2026-11-22.json`, two runs at once in one lane (four
    scenarios failed): `screen.gang_fast_path` 8.23%, `parse.mixed_1mb`
    7.95%, `screen.parse_execute_mixed_1mb` 10.7%.
  - `busy-after-2026-11-22.json`, run alone and labeled busy only by the
    old after-run rule (before [2.81, 3.84, 5.04]), so the nearest thing
    to a clean repeat: `screen.gang_fast_path` 7.81%,
    `screen.parse_execute_mixed_1mb` 5.86%. Every other in-process time
    metric in it is within 4%. Its app rates show both false regressions
    (`app.stress_normal_10tabs` 57%, `app.stress_clearcodes_1tab` 33%)
    and false improvements (buffer, htop, normal_1tab).

  Under the old rule `screen.gang_fast_path`'s threshold was max(5%, 3 x
  4.8%) = 14.4% and none of its three readings would have been flagged.
  That widening applied to the best would flag nothing in the clean repeat
  (busy-after), but would still flag the forced run's
  `draw.attributed_strings_truecolor_ligatures` (6.75% against 5%) and the
  collided run's `screen.parse_execute_mixed_1mb` (10.7% against 7.7%). What
  follows for the owner's choice of threshold: on this evidence a fixed 5%
  on the best sample flags a clean repeat on `screen.gang_fast_path`. The
  alternatives are a wider threshold for best-of metrics, the old widening
  by spread applied to the best, or requiring a quiet candidate and a
  rerun before a regression counts. The code implements the fixed 5% as a
  proposal until he chooses (owner-queue.md Q23 item 3).

**A change measured both ways (2026-11-22).** The nil test added to
`-[iTermMutableAttributedStringBuilder setAttributes:]` is on the path the
three draw scenarios measure. Against the baseline, on a machine that was
not quiet (load average about 6, the owner's programs running), the tip
read 5.9% worse on `draw.attributed_strings_truecolor_ligatures` in two
runs. To separate the change from the machine, the three scenarios were
then run five times back to back in one lane, with the one line present,
absent, absent, present, present (best and median of ten samples, ms per
frame):

| Run | mono | truecolor | truecolor with ligatures |
|---|---|---|---|
| with | 2.873, 2.999 | 41.364, 41.849 | 64.887, 66.628 |
| without | 2.987, 3.099 | 40.706, 41.596 | 64.276, 66.060 |
| without | 2.946, 3.009 | 41.213, 41.670 | 64.428, 66.189 |
| with | 2.855, 3.095 | 40.927, 42.269 | 65.884, 66.558 |
| with | 2.892, 3.029 | 41.358, 41.988 | 65.658, 66.778 |

Without the line the ligatures scenario was still about 3.8% over the
baseline's best, so most of the 5.9% was the machine. The rest is small
and has no one direction: with the line, ligatures was slower in every
run (by 0.5 to 1.6 ms on the best, about 0.5 ms on the median, under 1%
of the median), mono was faster in every run (by 0.05 to 0.13 ms on the
best, about 3%), and truecolor showed no order. Two and three runs a side
do not settle whether either difference is real. A lesson for comparisons:
a candidate measured on a machine less quiet than the baseline's reads
worse, and only runs of both versions under the same conditions tell a
change from the machine.

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
runner. `flood` gives no iteration rate: `yes` writes no iteration counts, so
the script always reported 0 for it. Latency is not measured: the script's latency figures come only from
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
its reasons (after the run also the rule that judged it, every sample taken
while waiting for the load to settle, and when it settled), and per scenario
its status, the load average when it finished, and, per metric, the unit, which
direction is better, every sample and a summary (median, minimum, maximum,
MAD, robust relative spread, the best sample and the statistic compared;
results written before 2026-11-22 lack the last two, and `perf_compare.py`
computes them from the samples instead of reading them). Results go to `tmp/perf-baseline/results/` by
default. Where the baseline file is kept once taken is for the owner to
decide.

**Quiet machine.** A run is labeled a baseline only if, before the first
scenario and after the last: the load average is at most a quarter of the
logical CPUs; `memory_pressure` reports at least 30 percent free; no
`xcodebuild`, `swift-frontend`, `clang`, `ld` or similar build process is
running; the Mac is on AC power, not in Low Power mode, and not thermally
limited; and the tree has no uncommitted changes outside `docs/`. Before the
run both the 1- and the 5-minute averages count. After the run only the
1-minute average does, because the app scenarios themselves (thirty launches
under stress load, one with ten tabs) keep the 5-minute average over the
limit for minutes, so a run that included them could never be a baseline.
The runner polls every 15 seconds for up to 3 minutes
(`after_settle_seconds`, `after_poll_seconds`) for the 1-minute average to
come back under the limit; if it does not, the run is labeled `not a
baseline: machine became busy during the run`. Every other condition must
hold in every sample taken while waiting, and a failure of one ends the wait
at once. Load from something else that stopped before the 1-minute average
settled is not caught by this, however heavy it was; the per-scenario load
averages in the result show where load rose.
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
scenario and metric. Which statistic a metric is judged on follows from its
unit, in one place, `statistic_for` in `perf_lib.py`.

Decided by the owner on 2026-11-22: time and rate metrics (units `s`,
`ms`, `us`, `ns`, `iterations/s`) are estimated by the best sample, the
minimum when lower is better and the maximum when higher is better, and
compared best against best. In his words: "Given the variance you should
take the fastest time, since that's our best estimate."

Proposed, not confirmed by the owner (owner-queue.md Q23 item 3), and
implemented as such:

- A best-of metric whose best is worse by more than 5% is a regression,
  better by more than 5% an improvement.
- Spread never makes a best-of row inconclusive and does not widen its
  threshold; it is reported, with both medians.
- Memory and count metrics (`kB`, `count`, and any unit not listed) keep
  the median: a regression is a median worse by more than max(5%, 3 x
  noise), noise being the larger robust relative spread (1.4826 x MAD /
  median) of the two runs, and more than 10% noise is inconclusive.
- Fewer than five samples on either side is inconclusive, for both kinds.

The best is always computed from the samples, so older result files compare
the same way. Every scenario named in
either file gets at least one row. A scenario that failed in the candidate
(crashed, timed out, its test failed, or any status other than ok or
skipped) gives `failed in candidate` with the recorded reason, whatever the
reference holds; if the reference failed too, the note says `also failed in
reference`, so a before and after with the same failure does not read as
clean. A metric an otherwise successful scenario no longer reports gives
`missing in candidate`. Both block like a regression (exit 1). A scenario
the candidate skipped (the app scenarios are skipped while an instance of
the checkout's own `Build/<configuration>/iTerm2.app` is already running)
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
running, and on AC power. Other iTerm2 instances may stay open:
`run_stress_test.sh` launches a new instance of the app under test with
`open -n`, addresses it with AppleScript by its path (which reaches the
instance running from that path, not another copy with the same bundle
identifier) and finds, samples and quits it by its PID. It refuses to start
only while an instance of the same app path is already running. Its
`--inject` option sends Page Up and Page Down through System Events, which
deliver keys to whatever app is frontmost; the script sends one only when
the test instance is frontmost at the moment it checks, so a focus change
between the check and the key can still send one key to another app. The
baseline does not use that option. In a checkout at the commit to measure
with a clean tree (`docs/` aside, and including the submodule pointers: a checkout whose
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
add `--scenarios 'parse.*,screen.*,draw.*,memory.*'`;
after a build has been done once, `--skip-build` saves the build.
