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
  confirmed regression blocks the commit. The rule was decided by the
  owner on 2026-11-22. Time and rate metrics are estimated by their best
  sample (“Given the variance you should take the fastest time, since
  that's our best estimate.”). On the threshold he chose “per-scenario
  variation plus a back-to-back confirmation”: a metric worse than the
  reference by more than the larger of 5% and that scenario's own
  variation is a suspected regression, and it counts only if runs of both
  versions made back to back on the same machine show it again (section
  3, **Comparison** and **Confirming a suspected regression**). A
  suspected regression blocks until that confirmation run clears it. How a
  scenario's variation is measured is our choice, not the owner's.
  Still proposals: keeping the median for memory and counts, the
  five-sample floor, and that spread never makes a best-of row
  inconclusive.
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
file is `tools/swift_migration/perf_baselines/baseline-2026-11-22.json`,
committed there on the owner's word (“Put the baseline with other
port-related files”, 2026-11-22). Best is the fastest sample: the minimum where lower is
better, the maximum for the iteration rates. The bold figure in each row is
the one `perf_compare.py` compares (below, **Comparison**): Best for time
and rate metrics (decided), Median for memory and counts (proposed). For
a best-of row, how far the worst sample but one lies from Best is the
scenario's variation, which sets its threshold (below, **Comparison**);
rows
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
  `app.stress_clearcodes_1tab` 870, 752, 1177, 764 and 851. Rates are
  estimated by their best sample (2340, 1890 and 1177 here), and each
  scenario's threshold is the larger of 5% and how far its worst sample
  but one lies below its best (below, **Comparison**): 59.27%, 42.65%
  and 35.09% for these three. So a candidate whose runs all land on the
  slow level reads no change. Under the flat 5% that the code applied before the
  owner's decision, a clean five-run candidate showed a false regression
  on at least one of these three rates about 70% of the time, if the level
  of each run is random (each misses the fast level with probability 0.8
  to the fifth power, about 0.33). What the per-scenario threshold does
  not protect against:
  - A real regression smaller than the scenario's variation. On these
    three rates the best must fall by 35% to 59% before a single
    comparison flags anything; the harness can only catch a large
    regression there. The confirmation is more sensitive (below,
    **Confirming a suspected regression**), but it runs only after a
    single comparison has suspected something.
  - A fast outlier. One fast candidate run reads as an improvement and
    hides a real regression in the rest. A fast outlier in the reference
    no longer makes every later candidate look slower; it widens that
    scenario's threshold instead, which hides more. Setting aside the
    reference's worst sample does not help here: on these rates the fast
    sample is the best, not the worst. "These three rates"
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
- The first of the ten in-process samples is the slowest in 4 of the 8
  in-process best-of metrics of the baseline: `screen.gang_fast_path`,
  `screen.char_at_a_time` (16.149% above the best, the next slowest
  4.04%) and both truecolor draw scenarios. Taken whole, the reference's
  range would let that one sample set the threshold (16.149% for
  `screen.char_at_a_time`), so the reference's single worst sample is set
  aside before the range is taken (below, **Comparison**). The in-process
  thresholds are then 5% to 10.18% against this baseline. A slowdown
  smaller than a scenario's threshold is not flagged by a single
  comparison.
- A busy machine slows the fastest run too, not only the typical one, and
  a measure taken from one run's samples does not see that; that is what
  the confirmation (below) is for. Three other result files of 2026-11-22
  in `tmp/perf-baseline/results/` hold app and test code identical to the
  baseline's (only tool commits differ). Compared with
  `perf_compare.py --allow-non-baseline`, these are the false suspected
  regressions on time and rate metrics (memory and counts are not in the
  table) under the flat 5%, under the whole range of the reference (the
  first measure tried), and under the range with the worst sample set
  aside (the measure the code uses):

  | File | Conditions | Flat 5% | Whole range | Range without the worst sample |
  |---|---|---|---|---|
  | `forced-2026-11-22.json` | load average about 8 (before [4.87, 7.77, 8.39]), the owner's programs running | 3: `screen.gang_fast_path` 7.77%, `draw.attributed_strings_truecolor` 5.74%, `draw.attributed_strings_truecolor_ligatures` 6.75% | 0 | 2: `screen.gang_fast_path` 7.77% against 6.99%, `draw.attributed_strings_truecolor_ligatures` 6.75% against 5.17% |
  | `collided-2026-11-22.json` | two runs at once in one lane (four scenarios failed) | 3: `screen.gang_fast_path` 8.23%, `parse.mixed_1mb` 7.95%, `screen.parse_execute_mixed_1mb` 10.7% | 1: `screen.parse_execute_mixed_1mb` 10.7% against 7.71% | 2: `screen.gang_fast_path` 8.23% against 6.99%, `screen.parse_execute_mixed_1mb` 10.7% against 6.42% |
  | `busy-after-2026-11-22.json` | run alone, labeled busy only by the old after-run rule (before [2.81, 3.84, 5.04]): the nearest thing to a clean repeat | 4: `screen.gang_fast_path` 7.81%, `screen.parse_execute_mixed_1mb` 5.86%, `app.stress_normal_10tabs` 57.0%, `app.stress_clearcodes_1tab` 33.3% | 0 | 1: `screen.gang_fast_path` 7.81% against 6.99% |

  In all, 10, 1 and 5. Setting the worst sample aside brings back four
  false suspicions that the whole range hid, all on in-process scenarios
  run on a busier machine; it was chosen anyway, because with the whole
  range a single slow sample in the committed baseline would have set the
  threshold of every later comparison (16.149% for
  `screen.char_at_a_time`), and a false suspicion costs a confirmation
  run while a missed regression costs nothing that anyone sees. The
  measure was not tuned further. Of the false improvements in
  `busy-after` (flat 5%: buffer, htop and normal_1tab), both range
  measures keep two (`app.stress_buffer_1tab` 118%,
  `app.stress_htop_unthrottled_1tab` 58%). The memory rows of `busy-after` are judged on the median by an
  unchanged rule and still read four suspected regressions in resident
  size (`app.stress_buffer_1tab` and `app.stress_flood_1tab` steady,
  `app.stress_clearcodes_1tab` peak and steady). Two candidates of the
  same day hold the one-line change measured below, which costs at most
  about 1%, on a machine that was not quiet: `candidate-draw-2026-11-22.json`
  reads 3, 0 and 2 (the same three measures), `candidate2-2026-11-22.json`
  2, 0 and 2: under the final measure, and in `candidate2` under the flat
  5% too, `draw.attributed_strings_truecolor_ligatures` and
  `screen.gang_fast_path`; under the flat 5% `candidate-draw` also flags
  `screen.parse_execute_mixed_1mb` (5.54%). A busy enough candidate passes any of
  these thresholds; a single comparison can therefore only suspect a
  regression, and only the confirmation decides. Other measures were
  tried on the same files (results in this order: forced, collided,
  busy-after): three times the robust relative spread,
  the old widening applied to the best, flags 1, 1, 1 and misses the
  two-level rates, whose spread around the median is 0.9%; the distance
  from the best to the median flags 3, 3, 3; the distance from the best
  to the quartile on the slow side (Python's `statistics.quantiles` with
  `method='inclusive'`), taken from each of the two files and the larger
  used, 2, 3, 2. All three of these take the larger of the two files'
  figures; the measure chosen takes the reference's only.

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
change from the machine. Given to `perf_compare.py --confirm` (base the
two runs without the line, candidate the three with it, and the other
way round), all three scenarios read no change: ligatures 0.95% worse,
mono 3.09% better and truecolor 0.54% worse, each against the 5% floor
(the bests of the runs on each side are within 1.6% of each other); the
other way round, mono 3.19% worse, the others under 1%. No pair of these
five files flags anything in either direction under the flat 5% or
either range measure.

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
default, which git ignores. A baseline, once taken, is copied to
`tools/swift_migration/perf_baselines/` and committed.

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

Decided by the owner on 2026-11-22:

- Time and rate metrics (units `s`, `ms`, `us`, `ns`, `iterations/s`) are
  estimated by the best sample, the minimum when lower is better and the
  maximum when higher is better, and compared best against best. In his
  words: “Given the variance you should take the fastest time, since
  that's our best estimate.”
- The regression rule. Asked whether to keep a flat 5% for every scenario
  or to use “5% or that scenario's own run-to-run variation, whichever is
  larger” and count a flagged regression “only if it shows up again when
  both versions are run back to back on the same machine”, he answered:
  “per-scenario variation plus a back-to-back confirmation”. So the
  threshold of every compared metric is the larger of 5% and the
  scenario's variation, and one comparison of a candidate against a
  reference can only give `suspected regression`; a regression counts only
  when `perf_compare.py --confirm` confirms it (below, **Confirming a
  suspected regression**).

Our choices, not the owner's, within that rule:

- The variation of a best-of metric is how far the reference's worst
  sample lies from its best, in percent of the best, after the single
  worst sample of the reference is set aside (when it has five samples or
  more, which a compared row always has). A best-of row is then a
  suspected regression when its candidate best is more than 5% worse than
  the reference's best and, where the reference spreads more than 5%,
  worse than the reference's worst sample but one. Why this measure: a
  range from the best covers the two-level app rates (a spread around the
  median sees one level only) and removes half of the false regressions
  on identical code ("Read with care", above); only the reference's
  samples count, so a candidate made noisy by its change cannot widen its
  own threshold; and setting aside one sample keeps a single hiccup in
  the committed baseline, often XCTest's slow first iteration, from
  setting the threshold of every later comparison. Its costs are also in
  "Read with care": the app rates need a drop of 35% to 59% before
  anything is flagged, two slow samples in the reference still widen the
  threshold, and a slowdown smaller than the variation is not flagged by
  a single comparison.
- Memory and count metrics (`kB`, `count`, and any unit not listed) keep
  the median, still a proposal (owner-queue.md Q23 item 3). Their
  variation is three times the noise, noise being the larger robust
  relative spread (1.4826 x MAD / median) of the two sides, reference and
  candidate both (unlike the best-of measure, so here a noisy candidate
  does widen its own threshold; this is the earlier proposal, kept as it
  was), so their threshold, max(5%, 3 x noise), is the rule they had
  before, now read as
  the decided “5% or the scenario's variation”. More than 10% noise is
  inconclusive for them, also a proposal.
- Proposed, not confirmed by the owner (owner-queue.md Q23 item 3): spread
  never makes a best-of row inconclusive.
- Proposed, not confirmed by the owner (the same item): fewer than five
  samples on either side is inconclusive, for both kinds.

Thresholds of the best-of metrics against the baseline of 2026-11-22, as
`perf_compare.py` computes them:

| Scenario | Metric | Threshold | Whole range (not used) |
|---|---|---|---|
| `screen.char_at_a_time` | `time` | 5% (floor; 4.04%) | 16.149% |
| `draw.attributed_strings_truecolor_ligatures` | `time_per_frame` | 5.170% | 8.338% |
| `screen.parse_execute_mixed_1mb` | `time` | 6.417% | 7.706% |
| `app.stress_htop_unthrottled_1tab` | `iterations_per_sec` | 6.685% | 9.749% |
| `draw.attributed_strings_truecolor` | `time_per_frame` | 6.932% | 7.907% |
| `screen.gang_fast_path` | `time` | 6.992% | 11.159% |
| `draw.attributed_strings_mono` | `time_per_frame` | 7.225% | 7.939% |
| `memory.scrollback_fill_20k` | `clock_monotonic_time` | 7.379% | 7.855% |
| `app.stress_buffer_1tab` | `iterations_per_sec` | 8.280% | 9.554% |
| `parse.mixed_1mb` | `time` | 10.180% | 11.379% |
| `app.stress_clearcodes_1tab` | `iterations_per_sec` | 35.089% | 36.109% |
| `app.stress_normal_1tab` | `iterations_per_sec` | 42.646% | 43.968% |
| `app.stress_normal_10tabs` | `iterations_per_sec` | 59.274% | 59.274% |

Each row of the report shows the noise, the variation and the threshold.

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
macOS versions give a warning. For the before and after of a port,
compare the port's run with the committed baseline, and confirm anything
suspected as below.

Exit status of a single comparison: 0 when nothing is suspected and
nothing failed; 1 for any `suspected regression`, `failed in candidate` or
`missing in candidate` row; 2 when the files are not comparable or cannot
be read. A suspected regression keeps exit status 1, so nothing that reads
the status can take it for a pass; the output names the suspected rows
and says how to confirm them. It stops blocking only when a valid
confirmation run (below) gives `no change`, `not confirmed` or
`improvement` for every one of them. An `inconclusive` confirmation does
not clear it: the suspicion stands until a confirmation gives one of
those verdicts or `confirmed regression`.

**Confirming a suspected regression.** Measure both versions in turn, back
to back, on the same machine:

1. Hold one lane for the whole procedure and change nothing in its build
   settings. Put the base version's tree and the candidate's tree in it
   alternately (a commit and its parent, or the change applied and
   removed), at least twice each, and interleaved, for example base,
   candidate, candidate, base, base, candidate. For the app scenarios use
   at least three each (below).
2. After each switch, measure with the same options every time, limited
   to the suspected scenarios, each run to its own file:

       python3 -B tools/swift_migration/perf_baseline.py run \
           --scenarios 'screen.gang_fast_path' \
           --output tmp/perf-baseline/results/confirm-base-1.json

   The runner builds `Deployment` first; `--skip-build` must not be used,
   since the tree changed. Name the files so that each side is clear.
3. Compare all of them at once:

       cd tmp/perf-baseline/results &&
       python3 -B ../../../tools/swift_migration/perf_compare.py --confirm \
           --base confirm-base-1.json confirm-base-2.json ... \
           --candidate confirm-candidate-1.json confirm-candidate-2.json ...

Per metric, `--confirm` pools each side's samples and compares the pooled
statistic (best or median, as above) against the larger of 5% and the
variation between the base runs, not within them (our choice, like the
single comparison's measure): for a best-of metric, how far the worst
base run's best lies from the best base run's best; for a median metric,
the same spread of the base runs' medians or three times the noisiest
single base run's robust relative spread, whichever is larger (the second
term keeps the single comparison's noise rule; pooling the runs into one
MAD would count the difference between runs twice; candidate runs are
left out so that a candidate made noisy by its change cannot widen its
own threshold, though the noisiest run of either side still decides the
10% inconclusive limit). It also takes each run's own statistic. The
verdict:

- `confirmed regression`: the pooled candidate is worse by more than the
  threshold, and every candidate run's statistic is worse than every base
  run's (the best candidate run is worse than the worst base run).
- `not confirmed`: worse by more than the threshold pooled, but some
  candidate run is as good as some base run. It is named in a warning and
  does not block.
- `improvement`: better by more than the threshold pooled and in every
  run; better pooled but not in every run reads `no change`, with a note.
- `no change`, `inconclusive` (fewer than five samples in any run, or a
  median metric over 10% noise), and the scenario verdicts of a single
  comparison, where a failure or a missing metric in any candidate run
  gives `failed in candidate` or `missing in candidate`, and a skip in any
  run gives `skipped in candidate`.

For a best-of metric the run-by-run condition always holds once the pooled
condition does: a pooled candidate best worse than the best base run's
best by more than the spread of the base runs' bests is worse than every
base run's best. It binds for median metrics. A cost for median metrics:
the pooled median is compared against a spread measured from the best
base run's median, so base runs that differ widen the threshold more than
the pooled median moves. With base run medians of 100 and 120 (lower is
better) the variation is 20%, and candidate run medians of 125 and 126
read no change, about 14% worse than the pooled base median of 110,
though every candidate run is worse than every base run.

What the confirmation can see. A run's best barely moves with a slow
sample or two, so the bests of interleaved runs of one version lie close
together: on the draw runs above, within 1.6%, so the threshold there was
the 5% floor, below the single comparison's 5.2% to 7.2% for those
scenarios. A run that was busy throughout moves its best and widens the
threshold by as much: with the baseline's `screen.gang_fast_path` run and
the much busier one of `candidate-draw-2026-11-22.json` as the two base
runs, whose bests are 8.57% apart, a candidate 40% slower in every run is
confirmed, and one 8% slower would not be. What it cannot see:

- A slowdown below the spread of the base runs' bests, at least 5%.
- Chance, when the runs of one version differ by more than 5%. For a
  best-of metric the run-by-run condition adds nothing, so on identical
  code a confirmation fires whenever every candidate run's best happens
  to be worse than every base run's by more than the spread of the base
  runs' bests. On the two-level app rates, if run bests sat exactly on
  two levels and one sample in five reached the fast one, independently,
  a run would reach it with probability about 0.67, and the chance is
  that of both base runs fast and both candidate runs slow: 0.67 squared
  times 0.33 squared, about 5% per rate with two runs a side, about 1%
  with three. That is a lower bound. Run bests also vary within a level,
  and once they vary by more than 5% every ordering of the 2k runs (k a
  side) becomes about equally likely, so the chance approaches 1 in
  C(2k, k), the chance that the k candidate runs are exactly the k worst:
  1 in 6 with two runs a side, 1 in 20 with three (a reviewer's
  simulations with 1% and 3% jitter on each sample gave 6.4% and 1.5%,
  and 10% and 3.2%). So the chance per rate is at least about 5% (1% with
  three runs a side) and up to 1 in 6 (1 in 20). The same bound holds in
  process when interleaved runs drift by more than 5%. The other way, a
  base run at the slow level widens the threshold to that rate's 35% to
  59%. Hence at least three runs a side for the app scenarios.
- Anything the single comparison did not suspect first: the confirmation
  is run only on suspected scenarios.

`--confirm` needs no baseline label. It refuses (exit 2) fewer than two
files a side, a file named on both sides or twice on one side (compared by
real path), and files that differ in
schema, configuration, architecture, machine, or the runner's
`iterations`, `app_runs` and `app_duration_s`, and it takes no `--allow-`
option. It warns when the runs were made in different lanes or
checkouts, when every run of one side started before every run of the
other (not interleaved, so a drift of the machine over time would read as
a change), when both sides record the same commit and uncommitted paths
(probably the same tree twice), when a side records more than one
tree, and, naming them, when runs were measured on a busy machine.

A confirmation with any of these warnings (runs not interleaved, more
than one tree on a side, different lanes or checkouts, a busy machine,
the same tree on both sides) is not valid evidence, whatever its
verdicts: fix the cause and rerun it. Files that were not made by this
procedure prove nothing either: given `--base` the baseline and the
busy-after run and `--candidate` the two candidate files of 2026-11-22,
none of them back to back, a reviewer got two confirmed regressions on
code that changed by at most about 1%.

Exit status: 0 when nothing is confirmed and nothing failed; 1 for any
`confirmed regression`, `failed in candidate` or `missing in candidate`
row; 2 when not comparable or unreadable. Exit status 0 with warnings is
not a pass, for the reason above.

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
