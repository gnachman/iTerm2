# Integer sanitizer findings

Part of the Objective-C to Swift migration process. Read
[README.md](README.md) first.

The result of the integer discovery runs that
[translation-rules.md §1](translation-rules.md) asks for: every place where
the integer sanitizers saw truncation, sign change, overflow or a bad float
conversion while the whole ModernTests suite ran on the Objective-C, each
read, judged, and paired with what a port of that line must do. Sections 1
to 4 are the first run (no sign changes, no stress inputs); sections 7 to 10
are the second run, which added both.

## 1. The run

| | |
|---|---|
| Date | 2026-11-20 |
| Command | `tools/swift_migration/sanitizer_tests.sh integer --parallel` (whole suite, ten test hosts) |
| Run directory | `tmp/sanitizers/runs/integer-20261120-014751` (not committed) |
| Checks | `signed-integer-overflow,implicit-conversion,float-cast-overflow,integer-divide-by-zero,shift,bounds`, recover mode, Objective-C and C only (Swift is not instrumented) |
| Tests | 12324 executed: 11639 passed, 1 failed (`RuntimeSnapshotTests.testHeaderRecordsArchitectureAndConfiguration`, an environment effect; see `bugs.md`), 684 skipped |
| Reports | 47 at 14 locations, all in scope: implicit signed truncation 9 locations (22 reports), float-cast overflow 3 (23), signed overflow 2 (2); no unsigned truncation, divide by zero, shift or bounds report |
| Summary data | `tmp/sanitizer-collection/integer/` (summary.txt, groups.json, analysis.txt) |

A count is the number of test host processes in which the location fired:
the runtime prints a location once per process, and there were ten.

Line numbers are those of the tree the run used and were checked against the
current tree when this file was written.

## 2. The rule a port follows

The owner's rule of 2026-11-20 (decisions.md): in release builds every
arithmetic and conversion helper (`it_add`, `it_subtract`, `it_multiply`,
`it_negate`, `it_shiftLeft`, `it_narrow`, `it_floatToInteger`) does what the
C it replaces does in practice: integer operations wrap, narrowing
truncates, and a left shift drops the bits shifted out and masks its count
as the hardware does (the table is in
[translation-rules.md §1](translation-rules.md)). A float converted to an
integer is the exception: for NaN and out-of-range values C has no fixed
result, so `it_floatToInteger` clamps, giving 0 for NaN and the nearest
bound of the type otherwise, on both processors (decisions.md, 2026-11-20,
amending the rule).
In Development, Beta and Nightly builds and in tests the same helpers
assert on every such event. So, for the sites below:

- **An intended wrap or truncation** is written with the wrapping operator
  (`&+`, `&-`, `&*`, `&<<`) or `init(truncatingIfNeeded:)` /
  `init(bitPattern:)`, with a comment saying what relies on it, and **never**
  with an asserting helper: the helper would fire every time the code does
  what it was written to do, which here means in ordinary tests.
- **A real bug is fixed in Objective-C first**, in its own `fix` commit with
  a failing test, before the port. Several of the bugs below fire in every
  run of common tests, so a faithful port through the asserting helper
  would make those tests fail in Development builds; fixing first is the
  only order that keeps the gate green without weakening anything.
- **Benign but unintended** sites (the code works by accident) are either
  fixed first the same way or ported with the explicit non-asserting form
  that reproduces the C result exactly. Each entry says which.

## 3. The fourteen locations

Kinds use the sanitizer's names: *implicit signed truncation* (a value
changed when stored into a narrower or signed type), *signed overflow*,
*float-cast overflow* (a float converted to an integer type that cannot
hold it, including NaN).

| # | Location | Expression | Kind | Values seen | Count | Verdict |
|---|---|---|---|---|---|---|
| 1 | `sources/PTYSession/PTYSession.m:17733` | `result.height = _screen.height + roomToGrow / cellSize.height;` in `-theoreticalGridSize` | float-cast overflow | NaN to `int` | 8 | real bug, fixed |
| 2 | `sources/PTYSession/PTYSession.m:17737` | `result.width = _screen.width + roomToGrow / cellSize.width;` in `-theoreticalGridSize` | float-cast overflow | NaN to `int` | 8 | real bug, fixed |
| 3 | `sources/ScreenChar/ScreenChar.m:421` | `encoding = NSUTF16LittleEndianStringEncoding;` (`int encoding`) in `CharArrayToString` | implicit signed truncation | 2483028224 to -1811939072 | 8 | benign, unintended; fixed |
| 4 | `sources/MetalRenderer/Renderers/iTermBackgroundColorRenderer.mm:160` | `static_cast<NSUInteger>(tState.suppressedBottomHeight * tState.cellConfiguration.scale - tState.margins.top)` in `-drawWithFrameData:transientState:` | float-cast overflow | -12 and -36 to `NSUInteger` | 7 | real bug (latent), fixed |
| 5 | `sources/VT100/VT100Grid.m:2556` | `char c = line[x].code;` in `-compactLineDump` | implicit signed truncation | 8217 to 25, 8239 to 47 | 4 | benign, intended |
| 6 | `sources/VT100/VT100Grid.m:2609` | `char c = line[x].code;` in `-compactLineDumpWithContinuationMarks` | implicit signed truncation | 9496 to 24 | 1 | benign, intended |
| 7 | `sources/Categories/NSStringITerm.m:695` | `const char high = fromhex([self characterAtIndex:i]) << 4;` in `-dataFromHexValues` | implicit signed truncation | 240 to -16 | 3 | intended wrap |
| 8 | `sources/SearchingFiltering/iTermFindOnPageHelper.m:424` | `b[byteIndex] \|= bit;` (`char *b`) | implicit signed truncation | 240 to -16, 128 to -128 | 2 | intended wrap |
| 9 | `sources/tmux/iTermTmuxLayoutBuilder.m:255` | `csum += *layout;` (`u_short csum`) in `-checksumForLayout:` | implicit signed truncation | 65571 to 35 | 1 | intended wrap |
| 10 | `sources/PTYSession/PTYSession.m:17871` | `return [[iTermController sharedInstance] indexOfTerminal:...];` from `- (int)screenWindowIndex` | implicit signed truncation | 9223372036854775807 (`NSNotFound`) to -1 | 1 | real bug (benign effect), made explicit |
| 11 | `sources/ContentAnalysis/iTermTextExtractor.m:1756` | `count < maxChars + width` in `-lineNumberWithStartOfWholeLineIncludingLine:respectContinuations:maxChars:` | signed overflow | 2147483647 + 80 | 1 | real bug, fixed |
| 12 | `sources/ContentAnalysis/iTermTextExtractor.m:1775` | `count < maxChars + width` in `-lineNumberWithEndOfWholeLineIncludingLine:respectContinuations:maxChars:` | signed overflow | 2147483647 + 80 | 1 | real bug (same cause as 11), fixed |
| 13 | `sources/Keyboard/iTermTermkeyKeyMapper.m:423` | `const char replacement = ((char *)data.bytes)[0] \| 0x80;` in `-dataBySettingMetaFlagOnFirstByte:` | implicit signed truncation | 226 to -30 | 1 | intended wrap |
| 14 | `sources/Keyboard/iTermStandardKeyMapper.m:315` | `const char replacement = ((char *)data.bytes)[0] \| 0x80;` in `-dataBySettingMetaFlagOnFirstByte:` | implicit signed truncation | 225 to -31 | 1 | intended wrap |

Totals: real bugs 6 locations (four causes: 1 and 2, 4, 10, 11 and 12);
intended wraps or truncations 7 (5, 6, 7, 8, 9, 13, 14); benign but
unintended 1 (3).

The real bugs and the benign but unintended site (1, 2, 3, 4, 10, 11, 12)
were fixed in Objective-C by the unit `integer-findings-fixes`
(`git log --grep 'Swift-Port: integer-findings-fixes'`), each with a test,
and no longer fire: a sanitizer run of the classes that fired them, and of
the new tests, reported none of them after the fixes. Their entries below
keep the finding and say what a port of the fixed code does. The intended
wraps (5 to 9, 13, 14) are unchanged and still fire.

## 4. Each location

### 4.1 `PTYSession.m:17733` and `:17737`: NaN converted to `int` (real bug)

`-theoreticalGridSize` adds `roomToGrow / cellSize.height` (and `.width`) to
the grid size. In the fixture sessions the cell size is zero (no font
metrics in a session without a real text view) and the screen and window
frames are equal, so the quotient is 0/0, NaN, and the sum is converted to
`int`. With a non-zero `roomToGrow` it would be an infinity. C leaves the
result undefined; arm64 gives 0 for NaN and saturates infinities, x86_64
gives `INT_MIN`. It fires in every session `TerminalWindowTestFixture`
makes, through `-[PTYSession updateConfigurationFields]`. Whether the app
reaches it with a zero cell size (before the text view has a font) is not
verified. Its `bugs.md` entry was removed when it was fixed.

Fixed by `integer-findings-fixes`: each dimension computes its growth
first and adds it only when it is finite, so a zero or non-finite cell size
gives the current grid size for that dimension (not 0, a 0x0 report to
CSI 19 t, and not `INT_MAX` or `INT_MIN`, which would also make DECST8C,
the other caller, loop over a huge width). Finite growth gives the same
result as before. Tests: `PTYSessionTheoreticalGridSizeTests`.

Port: compute `growth` as a `CGFloat`, add `growth.isFinite ? growth : 0`
to the grid dimension, and convert with `it_floatToInteger`, which can no
longer see NaN or infinity here; a finite value out of `Int32` range would
still assert, as it should.

### 4.2 `ScreenChar.m:421`: encoding stored in an `int` (benign, unintended)

`int encoding = NSUTF16LittleEndianStringEncoding;` truncates 0x94000100 to
-1811939072, and passing it on as `NSStringEncoding` sign-extends it to
0xFFFFFFFF94000100. The second conversion is a sign change, which this run
cannot see (section 5); a probe built with LLVM 22's sanitizer reports it
(`int` -1811939072 to `NSStringEncoding` 18446744071897612544) and shows
that `-initWithBytesNoCopy:length:encoding:freeWhenDone:` still decodes
correctly with the sign-extended value. So it worked, by accident. Its
`bugs.md` entry was removed when it was fixed.

Fixed by `integer-findings-fixes`: the variable is a
`const NSStringEncoding`, so Foundation now receives 0x94000100 itself
rather than the sign-extended value; the decoded strings are the same.
Tests: `CharArrayToStringTests`.

Port: pass `String.Encoding.utf16LittleEndian` (or the constant's raw
value) directly; no conversion and no helper.

### 4.3 `iTermBackgroundColorRenderer.mm:160`: negative value converted to `NSUInteger` (real bug, latent)

The conversion runs on every Metal draw. In every report
`suppressedBottomHeight` was 0, so the value was `-margins.top` (-12, -36),
and the result is used only inside
`if (tState.suppressedBottomHeight > 0)` (`:183`), so in the observed
cases it is discarded. When `0 < suppressedBottomHeight * scale < margins.top`
the negative value is used as a quad height: arm64's conversion gives 0
(nothing drawn) while x86_64 gives a value near 2^64 (a quad covering
everything), so the two slices of the shipping app disagreed. Its
`bugs.md` entry was removed when it was fixed.

Fixed by `integer-findings-fixes`: the height is computed by the inline
function `iTermBackgroundColorRendererSuppressedBottomPixels`
(`iTermBackgroundColorRenderer.h`), called only inside
`if (tState.suppressedBottomHeight > 0)`, once per draw and outside the
per-segment loop. It returns 0 when the difference is not positive, which
is what arm64 produced; x86_64 now also draws nothing there instead of a
quad covering everything. Non-negative values give the same result as
before. Tests: `BackgroundColorRendererSuppressedRegionTests`.

Port: the same guard (`pixels > 0 ? ... : 0`) before the conversion; the
conversion then sees only positive finite values.

### 4.4 `VT100Grid.m:2556` and `:2609`: `unichar` stored in `char` (benign, intended)

`char c = line[x].code;` truncates any code above 127, but the next line
replaces `c` with `'?'` whenever `line[x].code > 127`, so the truncated
value is never used. These are the compact debug dumps that tests compare.

Port: `CChar(truncatingIfNeeded: line[x].code)` with a comment that the
value is replaced for codes above 127; never `it_narrow`, which would assert
whenever a dump contains non-ASCII text. Testing the code before narrowing
gives the same output and is also acceptable.

### 4.5 `NSStringITerm.m:695`: hex nibble shifted into a `char` (intended)

`fromhex(...) << 4` is an `int` up to 240; stored in `const char` it keeps
its bit pattern (-16), and `high | low` then forms the byte that is
appended. The output bytes are correct.

Port: build the byte as `UInt8` (`UInt8(truncatingIfNeeded: nibble) &<< 4`,
or shift in `Int` and convert with `truncatingIfNeeded:`); never an
asserting helper. Swift reaches this method (`TmuxWorkgroupState`'s hex
decoding).

### 4.6 `iTermFindOnPageHelper.m:424`: bit set in a `char` buffer (intended)

`b[byteIndex] |= bit;` with `bit` up to 128 on a `char *`: the compound
assignment converts back to `char`, keeping the bit pattern. It is a
bitmap.

Port: treat the buffer as `UInt8`, where `|=` of a bit up to 128 cannot
overflow and needs no helper.

### 4.7 `iTermTmuxLayoutBuilder.m:255`: layout checksum (intended wrap)

tmux's layout checksum, written as in tmux: a 16-bit rotate and add, which
wraps by design. `*layout` is a `char`, signed on both Apple targets, so
bytes of non-ASCII names add negative values; tmux computes the same.

Port: `UInt16` arithmetic with `&+`, adding the byte sign-extended as C
does: `csum = csum &+ UInt16(truncatingIfNeeded: Int(Int8(bitPattern: byte)))`,
with a comment naming tmux's `layout_checksum`. Never an asserting helper,
which would fire for any layout longer than a few characters.

### 4.8 `PTYSession.m:17871`: `NSNotFound` returned as `int` (real bug, benign effect)

`-indexOfTerminal:` returns `NSNotFound` when the session's window is not
registered with `iTermController`; the `int` return makes it -1 on both
architectures (the low 32 bits of `NSIntegerMax`). The nine callers
(`PTYSession.m:6022`, `:18214`, `:21751`, `:21766`, `:27606`, `:28290`,
`:28360`; `PTYTab.m:9180`, `:9221`) pass it on as a window index for
notifications and reports. The truncation is unintended; -1 happens to be a
harmless "no window". This is the `NSNotFound` case translation-rules.md
names. Its `bugs.md` entry was removed when it was made explicit.

Made explicit by `integer-findings-fixes`:
`index == NSNotFound ? -1 : (int)index` returns exactly what the implicit
conversion returned, so every caller passes on the same value. Tests:
`PTYSessionScreenWindowIndexTests`.

Port: mirror the explicit form, `index == NSNotFound ? -1 : Int32(index)`
(or `it_narrow` for the second branch, where a window index never exceeds
`Int32`).

### 4.9 `iTermTextExtractor.m:1756` and `:1775`: `INT_MAX` plus the width (real bug)

`-locatedStringForWrappedLineEncompassing:targetOffset:`
(`iTermTextExtractor.m:2447`) passes `maxChars:INT_MAX` to
`-rangeForWrappedLineEncompassing:respectContinuations:maxChars:`, with the
comment "Use a large maxChars to ensure we get the full line". The two
helpers it calls treat only a negative `maxChars` as unlimited (then using
`INT_MAX - width`), so with `INT_MAX` the loop condition
`count < maxChars + width` overflows `int`. In practice it wraps to a
negative number, the condition is false, and neither loop runs: the caller
gets one row instead of the whole wrapped line. A C model of the loop gives
the same result at `-O0`, `-O2` and `-Os` on arm64 (the loop does not run
with `INT_MAX` and does run with -1), so release builds are not expected to
differ, though the app's own optimized code was not inspected. The model
keeps `width` opaque to the optimizer (a parameter of a function that is not
inlined); in the app it is opaque too, the result of the Objective-C message
`-widthOfWindowedRange`. Where the optimizer can see the operands, signed
overflow being undefined lets it compute the sum differently, so the
optimized result depends on that opacity. The test that
reached it, `iTermWordExtractorTest.testRegexMatchBridgesCJKWordBoundaries`,
passes because it does not depend on a wrapped line through this path.
Its `bugs.md` entry was removed when it was fixed.

Fixed by `integer-findings-fixes`, in the two callees rather than the
caller: each computes the limit once, before its loop, as
`(NSInteger)maxChars + width`, which cannot overflow, so `INT_MAX` (and any
other large limit, such as a large advanced setting passed by the semantic
history callers) means no limit. Every limit that did not overflow gives the
same result as before. This is a behavior fix: regular expression word
selection now matches across soft wraps. Tests: the `IntMax`, `LargeMaxChars`,
`NegativeMaxChars`, located string and regex word selection tests in
`TextExtractorTests`.

Port: compute the limit in `Int` (`Int(maxChars) + Int(width)`, bounded by
type) with the plain operator.

With the overflow fixed, `-locatedStringForWrappedLineEncompassing:targetOffset:`
no longer asks for the whole wrapped line: it examines at most max(20, 2 x the
screen height) rows (the data source's optional `height`, 0 if absent), centred
on the clicked row with unused rows on one side given to the other
(`iTermTextExtractorRegexWordSearchMaximumRows` and
`-rowsOfWrappedLineIncludingLine:maximumRows:` in iTermTextExtractor.m), so a
regular-expression word match is cut at that window and the work per click is
bounded; a click on a null cell takes the character-mode path so it cannot
select a word from another row (decisions.md, 2026-11-20).

### 4.10 `iTermTermkeyKeyMapper.m:423` and `iTermStandardKeyMapper.m:315`: meta bit (intended)

`((char *)data.bytes)[0] | 0x80` sets the high bit of the first byte; the
`int` result is stored back into a `char`, keeping the bit pattern, and
written into the data. The byte is what the terminal expects for
meta-sends-high-bit.

Port: `UInt8` arithmetic (`firstByte | 0x80`), which cannot overflow; no
helper. (Both methods read `bytes[0]` without checking for empty data; that
is not an integer finding and is preserved.)

## 5. Limits

- **Sign changes are covered by the second run (section 7), not the first.**
  Apple clang 21 (the Xcode toolchain, `Apple clang version 21.0.0
  (clang-2100.3.34.2)`) rejects `-fsanitize=implicit-integer-sign-change`
  for `arm64-apple-darwin` in its driver ("unsupported option") and leaves
  it out of `-fsanitize=implicit-conversion`, so the first run saw no sign
  change that keeps the width. The compiler and runtime still implement the
  check: given to the compiler itself,
  `-Xclang -fsanitize=implicit-integer-sign-change -Xclang -fsanitize-recover=implicit-integer-sign-change`,
  it instruments C, Objective-C (with ARC) and Objective-C++, and Xcode's
  own UBSan runtime reports it (kinds `implicit-integer-sign-change`, and
  `implicit-signed-integer-truncation-or-sign-change` when a conversion does
  both). The `integer-sign` mode of `tools/swift_migration/sanitizer_tests.sh`
  does this. No other compiler is involved: Homebrew LLVM 22, which the first
  run named as a possible route, was not needed.
- **What the sign-change check sees.** Implicit conversions only:
  assignments, initializations, arguments, returns, compound assignments,
  and the operand conversions of comparisons and arithmetic (a probe showed
  `int -1 < 1u` reported). It does not check explicit casts (`(int)x`), and
  it reports only when the value actually changes sign, so code that never
  runs with a negative or a too-large value reports nothing. Unsigned
  wraparound (`count - 1` on an empty collection) is not itself reported:
  `unsigned-integer-overflow` is not in the group, because it is defined
  behavior that a great deal of code relies on; the wrap shows up only where
  its result is then converted to a signed type (entries 7.10 and 7.12 are
  of that kind).
- **The stress harness itself was not run.** `tools/perf/run_stress_test.sh`
  refuses to start while any iTerm2 runs (`pgrep -x iTerm2`), drives the app
  with AppleScript `tell application "iTerm2"`, which resolves by name and,
  with the owner's iTerm2 running, would drive the owner's app (the
  Development build has the same bundle identifier,
  `com.googlecode.iterm2`), launches through LaunchServices (`open -a`),
  and its `--inject` option sends keys through System Events, which is
  accessibility automation. It cannot run beside the owner's iTerm2, and
  making it do so would mean replacing its whole driver.
- **Its inputs were replayed instead.**
  `ModernTests/StressStreamReplayTests.swift` feeds, through the pty path of
  a `VT100Screen` (parser, token executor, screen, line buffer) in reads of
  4093 bytes: a deterministic capture of `tools/perf/stress_load.py`'s
  output (`tests/stress_load_capture.txt`, made by
  `tools/perf/capture_stress_load.py`: every stress mode but `flood` and
  every dashboard mode, a fixed number of iterations each); the larger
  streams under `tests/` (prefixes of the biggest, to keep each test near a
  second); a small kitty graphics image sent the way
  `tests/transmitAndDisplay-kitty.txt` sends one; and generated streams that
  push integers to their extremes (CSI parameters up to 2147483639 for
  cursor, editing, margin, rectangle, mode, SGR and OSC sequences, long
  lines, many lines, combining marks, REP at its cap). It runs in the
  ordinary suite, so it was part of the second run.
- **What the replay does not reach.** The PTY reading and task code
  (`PTYTask`, the task notifier, the server processes), the text view
  (`PTYTextView` and its drawing), the Metal renderer drawing real frames,
  and every path that needs a window or a screen (`PTYSession`'s windowed
  configuration, resizing, the backing scale factor; 7.14 and 7.15 are
  reached only because the harness leaves that factor at 0). Only the
  harness, run by hand with the app, would cover those.
- **Open question for the owner.** Accept
  `ModernTests/StressStreamReplayTests.swift` in place of running
  `tools/perf/run_stress_test.sh` under the integer sanitizers for
  translation-rules.md section 1's discovery run, or run the harness by
  hand, against a sanitized build, with every other iTerm2 quit?
- **Coverage.** The sanitizer sees only code the tests execute, and at
  `-O0` the `bounds` check covers only indexing into arrays of known size;
  divide-by-zero and shift reported nothing in either run. The first run's
  684 skipped tests are the same as in
  [thread-baseline.md](thread-baseline.md) section 4; the second run skipped
  687, which were not compared test by test.
- **Use in dossiers.** Each location in sections 3 and 7 belongs in the
  arithmetic table of its unit's dossier, with the treatment given here.

## 6. Regenerating

1. Run `tools/swift_migration/sanitizer_tests.sh integer --parallel` (a
   build-lane job), then `tools/swift_migration/sanitizer_summary.py` with
   `--json` over the run's report files, which lists every location with its
   kind, message (the values), count, callers and tests.
2. Compare the locations with section 3 by file and expression, not only by
   line, since lines move. A new location is read and judged from the source
   before it is added; a location that no longer fires is removed, with the
   reason in the commit message.
3. For sign changes, run `tools/swift_migration/sanitizer_tests.sh integer-sign --parallel`
   instead (it includes everything the `integer` mode checks), and compare
   with section 7 the same way.

## 7. The second run: sign changes and stress inputs

| | |
|---|---|
| Date | 2026-11-20 |
| Command | `tools/swift_migration/sanitizer_tests.sh integer-sign --parallel` (whole suite, ten test hosts) |
| Run directory | `tmp/sanitizers/runs/integer-sign-20261120-181553` in the lane that ran it (not committed) |
| Checks | The first run's group plus `implicit-integer-sign-change` through `-Xclang` (section 5), recover mode, Objective-C, C and C++ only |
| Tests | 12464 executed: 11776 passed, 1 failed (`RuntimeSnapshotTests.testHeaderRecordsArchitectureAndConfiguration`, the environment effect in `bugs.md`), 687 skipped; includes `StressStreamReplayTests` |
| Reports | 79 at 22 locations, all in scope: sign change 9 locations (52 reports), truncation that also changes sign 5 (17), signed truncation 5 (7), float-cast overflow 2 (2), signed overflow 1 (1) |

Counts are processes, as in section 1. Seven of the 22 locations are the
intended wraps of section 3, unchanged (entries 5 to 9, 13, 14; the
`VT100Grid` dumps are now reported as `implicit-signed-integer-truncation-or-sign-change`
because a `unichar` stored in `char` also changes sign). None of the fixed
locations of section 3 fired. The other fifteen are new:

| # | Location | Expression | Kind | Values seen | Count | Reached from | Verdict |
|---|---|---|---|---|---|---|---|
| 7.1 | `sources/MetalRenderer/Glue/iTermMetalPerFrameState.m:1703:140` | `attributedStrings.count > 0 ? [... sourceColumnRange].location : -1` in `iTermEmitGlyphsAndSetAttributes` | sign change | `int` -1 to `NSUInteger` 18446744073709551615 | 10 | Metal frame state, no test frame on the stack | benign, unintended |
| 7.2 | same line, `:49` | `int nextAttributedStringLogicalStartIndex = <that>` | truncation and sign change | `NSUInteger` 18446744073709551615 to `int` -1 | 10 | the same | benign, unintended |
| 7.3 | `sources/VT100Screen/VT100ScreenState.m:151:31` | `_maxScrollbackLines = -1;` (`unsigned int`) in `-initForMutationOnQueue:` | sign change | -1 to 4294967295 | 10 | every `VT100Screen` | intended sentinel |
| 7.4 | `sources/MetalRenderer/Glue/iTermCharacterSource.m:838:20` | `destOffset -= destRowSize;` (`ssize_t -= size_t`) in `-bitmapForPart:` | sign change | `size_t` 18446744073709551440 to `ssize_t` -176 | 10 | `MetalGlyphContextResidueTests` | benign, relies on the bit pattern |
| 7.5 | `sources/ExternalSessionState/iTermExternalAttributeIndex.m:822:32` | `[encoder encodeUnsignedInt:-1];` in `-[iTermExternalAttribute data]` | sign change | -1 to 4294967295 | 6 | `iTermExternalAttributeSerializationTests`, `iTermASCIIStringTest` | intended sentinel (stored format) |
| 7.6 | same file `:621:50` | `[iTermURL urlWithData:urlData code:urlCode]` (`unsigned` to `int code`) in `+[iTermExternalAttribute fromData:]` | sign change | 4294967295 to -1 | 6 | the same | benign, unintended (sentinel mismatch) |
| 7.7 | same file `:1390:63` | `[[iTermURLStore sharedInstance] urlForCode:code]` (`int` to `unsigned`) in `-[iTermURL initWithData:code:]` | sign change | -1 to 4294967295 | 6 | the same | benign, unintended (same cause as 7.6) |
| 7.8 | `ThirdParty/PSMTabBarControl/source/NSAttributedString+PSM.m:115:28` | `options &= ~(1 << i);` (`NSUInteger options`) in `+newAttributedStringWithHTML:attributes:` | sign change | `int` -2 to `NSUInteger` 18446744073709551614 | 2 | `HTMLTabTitleEntityTests`, `WindowTitleHTMLTests` | intended bit mask |
| 7.9 | `sources/Metrology/iTermPreciseTimer.m:202:43` | `stringRepeatedTimes:millisWidth - numeric.length` (`int` parameter) in `iTermPreciseTimerLogString` | truncation and sign change | `NSUInteger` 18446744073709551615 to `int` -1 | 2 | a timer log, no test frame | benign, unintended |
| 7.10 | `sources/ProcessInfo/iTermWorkingDirectoryPoller.m:163:24` | `for (NSInteger i = _completions.count - 1; ...)` in `-didInferWorkingDirectory:valid:requestStamp:` | sign change | 18446744073709551615 to -1 | 1 | no test frame | intended idiom |
| 7.11 | `sources/Drawing/iTermTextDrawingHelper.m:4371:28` | `NSLocationInRange(cursorRow, ...)` (`int` to `NSUInteger`) in `-shouldDrawCursorConsideringBlink:` | sign change | -1 to 18446744073709551615 | 1 | `TerminalRendererTest.testLegacyRender` | benign, unintended |
| 7.12 | `sources/Announcements/iTermAnnouncementView.m:168:17` | `start = actions.count - 1;` (`int start`) in `-createButtonsFromActions:block:` | truncation and sign change | 18446744073709551615 to -1 | 1 | `AnnouncementDismissKeyTests` | intended idiom |
| 7.13 | `sources/VT100/VT100Grid.m:1203:13` | `cursor_.y + n` in `-moveCursorDown:` | signed overflow | 23 + 2147483639 | 1 | `StressStreamReplayTests.testCursorMovementWithHugeCounts` | real bug |
| 7.14 | `sources/InlineImages/VT100InlineImageHelper.m:353:29` | `*widthPtr = ceil((double)scaledSize.width / cellSize.width);` in `-getRequestedWidthInPoints:...` | float-cast overflow | inf to `int` | 1 | `StressStreamReplayTests.testSixel` | app-reachable (by reading; not verified in the app) |
| 7.15 | same file `:388:30` | `*heightPtr = ceil((double)scaledSize.height / cellSize.height);` in `-getRequestedHeightInPoints:...` | float-cast overflow | inf to `int` | 1 | the same | app-reachable (the same) |

Totals for the new locations: real bug 1 (7.13); app-reachable bug, by
reading, 2 (7.14, 7.15); benign but unintended 6 (7.1, 7.2, 7.6, 7.7, 7.9,
7.11); intended sentinels, masks, idioms or bit-pattern reliance 6 (7.3,
7.4, 7.5, 7.8, 7.10, 7.12).

## 8. Each new location

### 8.1 `iTermMetalPerFrameState.m:1703`: a ternary of `NSUInteger` and -1 (benign, unintended)

The two arms of `?:` have types `NSUInteger` and `int`, so the -1 arm is
converted to `NSUInteger` (7.1) and the result back to `int` (7.2), giving
-1 again. It fires on every frame whose row has no attributed strings. The
`location` arm is a column and fits in `int`.

Port: write the two arms in `Int32` explicitly,
`attributedStrings.isEmpty ? -1 : it_narrow(location, to: Int32.self)`; no
sign conversion remains. An `explicit` commit may do the same in Objective-C
first (`(int)` on the location arm).

### 8.2 `VT100ScreenState.m:151`: `-1` as the initial `maxScrollbackLines` (intended sentinel)

`maxScrollbackLines` is `unsigned int`; -1 makes it `UINT_MAX` until the
first configuration arrives (`VT100ScreenMutableState.m:641` replaces it
with the profile's value, an `int`). By reading, one use is a hazard that
the run did not reach: `[lineBuffer setMaxLines:self.maxScrollbackLines + self.height]`
(`VT100ScreenMutableState.m:7263`, restoring from a dictionary) wraps to
`height - 1` and passes that to an `int` parameter if it runs before any
configuration, and `dropExcessLinesWithWidth:` would then drop almost all
the restored scrollback. Whether restoration can run before the first
configuration was not checked; unsigned wraparound is not in the group
(section 5), so the run could not have reported it.

Port: `UInt32.max` (or `UInt32(bitPattern: -1)`) with a comment that it
means "not configured yet"; never `it_narrow(-1, ...)`, which asserts in
every test that makes a screen. The `+ height` at `:7263` uses `&+` with a
comment if ported as is, and is worth a test of restore-before-configure.

### 8.3 `iTermCharacterSource.m:838`: `ssize_t -= size_t` (benign, relies on the bit pattern)

`destOffset` is `ssize_t` and `destRowSize` is `size_t`, so the subtraction
is done in `size_t` and the result stored back, changing sign on the last
row (-176). The loop's `destOffset >= 0` test is what ends it, so the code
relies on the stored bit pattern; it is correct on every Apple target.

Port: do the arithmetic in `Int` (`destOffset -= Int(destRowSize)`), where
no conversion and no wrap happen; `destRowSize` is a row of a glyph bitmap,
so `Int(destRowSize)` cannot fail.

### 8.4 `iTermExternalAttributeIndex.m:822`, `:621` and `:1390`: the deprecated URL code (sentinel, then a mismatch)

`-[iTermExternalAttribute data]` writes 0xFFFFFFFF in the deprecated
`urlCode` slot (7.5). `+fromData:` reads it as `unsigned int urlCode`, and
its test `if (urlData.length || urlCode)` treats any nonzero code as
present, so for an attribute with no URL it calls
`+[iTermURL urlWithData:code:]` with the code converted to `int` -1 (7.6),
which converts it back to `unsigned` 4294967295 for
`-[iTermURLStore urlForCode:]` (7.7). No URL has that code, so the result is
nil, which is right. The cost is a store lookup under `@synchronized` for
every decoded attribute without a URL.

Port: the stored format must keep writing 0xFFFFFFFF
([stored-state.md](stored-state.md)): `UInt32.max` with a comment. The
reader reproduces the C exactly with `Int32(bitPattern:)` and
`UInt32(bitPattern:)`, never `it_narrow`, which would assert in every
round-trip test. A separate `fix` commit, test first, may treat 0xFFFFFFFF
as "no code" in `+fromData:`.

### 8.5 `NSAttributedString+PSM.m:115`: clearing a bit (intended)

`~(1 << i)` is an `int`, sign-extended to `NSUInteger`, so the mask keeps
every high bit and clears bit `i`. `i` indexes a short list of tags. For
`i` of 31 the `int` mask would be positive and clear the high 32 bits as
well; the list is far shorter than that.

Port: `options &= ~(UInt(1) << i)`; no conversion and no helper.

### 8.6 `iTermPreciseTimer.m:202`: padding width in `NSUInteger` (benign, unintended)

The padding count is `7 - numeric.length`, computed in `NSUInteger`. For a
text of 8 characters (for example `1234.5ms`) it wraps to `NSUIntegerMax`,
which becomes -1 as the `int` parameter (the value seen), and
`stringRepeatedTimes:` repeats zero times, which is the intended result.
Longer texts give -2, -3 and so on, with the same result. Debug timing
output only.

Port: `String(repeating: " ", count: max(0, millisWidth - numeric.count))`
in `Int`; same result, no conversion.

### 8.7 `iTermWorkingDirectoryPoller.m:163` and `iTermAnnouncementView.m:168`: `count - 1` on an empty collection (intended idiom)

Both compute `count - 1` in `NSUInteger` and store it in a signed variable,
so 0 gives -1 and the loop that follows does not run. In Swift the hazard is
smaller than it looks: `Array.count` (and an `NSArray`'s `count` as Swift
sees it) is `Int`, so `count - 1` is -1 for an empty collection, with no
trap and no conversion. The trap appears only if the port keeps the C's
unsigned type (`UInt(count) - 1`) or converts the difference to a narrower
type with a helper.

Port: subtract in the signed type. For the poller,
`for i in stride(from: completions.count - 1, through: 0, by: -1)`: the
plain `-` is bounded by type, since `count` is at least 0 and at most
`Int.max`, so `count - 1` cannot overflow `Int`; say so in a
`// bounded-by-type:` comment. For the announcement view, whose `start` is
`Int32`, `it_subtract(it_narrow(actions.count, to: Int32.self), 1)`, or
narrow and then use the plain operator with the same comment (`actions` has
at most two elements in that branch, so neither the narrowing nor the
subtraction can change a value).

### 8.8 `iTermTextDrawingHelper.m:4371`: a negative row tested with `NSLocationInRange` (benign, unintended)

`cursorRow` is -1 in the legacy renderer test (no cursor); converted to
`NSUInteger` it is never inside the visible range, so the function returns
NO, as intended. It works only because the converted value is huge.

Port: `cursorRow >= 0 && NSLocationInRange(Int(cursorRow), range)` gives
the same result for every input; never convert -1 to `UInt` with a helper.

### 8.9 `VT100Grid.m:1203`: `cursor_.y + n` overflows (real bug), and the same overflow in ICH and DCH

Found by the stress replay: `CSI 2147483639 B` on row 23. The wrapped sum
is clamped to row 0, so the cursor goes to the top instead of the bottom
margin. `-moveCursorRight:` and, on double-width lines, `-moveCursorLeft:`
and ECH have the same shape; CUU does not. Details, effects and the
reproduction are in `bugs.md` ("Cursor movement by a huge count overflows
`int`").

The same `x + n` overflow, found in review and not reported by the run, is
far more serious in `-[VT100Grid insertChar:externalAttributes:at:times:]`
(`VT100Grid.m:2698`) and `-[VT100Grid deleteChars:startingAt:]` (`:1945`,
`:1952`): from column 9 with a count of 2147483639 the clamp is skipped,
the number of cells to move is about -2^31, and `memmove` (`:2726`,
`:1987`) gets a size near 2^64. ICH, DCH, DECIC and DECDC reach it from
program output; SL and SR reach it with a left margin at column 9 or more.
The run did not report it because the replay put the cursor at column 5,
where the sum fits; the test now keeps it there on purpose until the fix
lands. Shown by reading and a C copy of the arithmetic, not against the
real code: `bugs.md` ("ICH, DCH, DECIC and DECDC with a huge count pass a
size near 2^64 to memmove").

Port: fix in Objective-C first, test first; the port then computes in
`Int` with plain operators (bounded by type: an `Int32` plus an `Int32`).

### 8.10 `VT100InlineImageHelper.m:353` and `:388`: infinite image size (app-reachable, by reading)

`-scaledSizeForDecodedImage:` divides the image size by the helper's
`scaleFactor`, which `-terminalAppendSixelData:` takes from
`config.backingScaleFactor`. The test harness's configuration leaves it 0,
so the scaled size is infinite and `ceil(inf / cellSize)` is converted to
`int` (arm64 gives `INT_MAX`, x86_64 `INT_MIN`). The app can give it 0 too:
`-[PTYSession updateConfigurationFields]` copies
`_view.window.screen.backingScaleFactor` (`PTYSession.m:20460`), which is 0
when the view has no window or the window has no screen, most likely for a
session in a tab that is not selected; other code guards the same value
(`PTYSession.m:23574`, `:10399`, `VT100ScreenMutableState.m:9269`). By
reading, an inline image arriving in such a session is sized wrongly (on
arm64 the grid's width and about as many rows; on x86_64 one cell), and
nothing hangs. Not verified in the app. `bugs.md` ("Inline images in a
session without a screen get an infinite size").

Port: fix in Objective-C first, test first: treat a zero or non-finite
scale factor as 1, as the other sites do; then `it_floatToInteger` sees
only finite values. A port of the unfixed code with the asserting helper
would fail `StressStreamReplayTests.testSixel`.

## 9. Found by the stress replay but not reported by a sanitizer

- **CHT and CBT loop once per count** (`VT100Terminal.m:2131`,
  `-[VT100ScreenMutableState backTab:]`). `CSI 2147483639 I` holds the
  session's queue for about 320 seconds in a Development test build, and,
  through the main thread's join, freezes the app's UI for that long.
  `bugs.md` has the measurement and the reasoning. `StressStreamReplayTests`
  sends CHT and CBT only counts up to 65536 until it is fixed.
- **The execution permits health check wraps `now &- last`**
  (`ExecutionPermits.swift:715`). It is Swift and so outside every
  sanitizer run here, but it is an unsigned wrap of exactly the kind this
  file is about: a holder that stores `lastHeardFrom` without the mutex,
  between the check's two reads, makes the difference nearly 2^64.
  Development builds and ModernTests then crash with "woke a holder not
  heard from for 18446744073.7s" (`crashInDebugBuilds` crashes only under
  `ITERM_DEBUG`); Beta, Nightly and Deployment builds log an RLog message
  and wake a holder that is already running. Seen once in `StressStreamReplayTests` under
  `tools/run_tests.expect`. `bugs.md` has the details.

## 10. The work list

Fixes needed before the units that contain them are ported. The first item
comes first by severity (memory corruption from program output); the rest
are most frequent first (report counts from section 7), with the ones found
without a report last, by severity:

0. ICH, DCH, DECIC and DECDC (`VT100Grid.m:2698`, `:1945`, `:1952`; no
   report, found in review by reading and a C copy of the arithmetic): a
   huge count from column 9 passes a size near 2^64 to memmove. Compute the
   sums in `NSInteger` or clamp the count first; `fix` commit, test first.
   In progress in the unit `integer-findings-fixes-2` (`bugs.md`).
1. `iTermMetalPerFrameState.m:1703` (20 reports, every frame): make the
   ternary's arms `int` explicitly; `explicit` commit, no behavior change.
2. `iTermExternalAttributeIndex.m:621`, `:1390` (12): treat the stored
   0xFFFFFFFF as "no code" in `+fromData:`; `fix` commit, test first,
   behavior unchanged except for the skipped lookup. Optional: the port can
   instead reproduce the C with bit-pattern conversions (8.4).
3. `iTermCharacterSource.m:838` (10): compute `destOffset` in signed
   arithmetic (`(ssize_t)destRowSize`); `explicit` commit.
4. `iTermPreciseTimer.m:202` (2): clamp the padding count at 0 in signed
   arithmetic; `explicit` commit.
5. `VT100InlineImageHelper.m:353`, `:388` (2): treat a zero or non-finite
   scale factor as 1; `fix` commit, test first (8.10, `bugs.md`).
6. `VT100Grid.m:1203` and the same shape in `-moveCursorRight:`,
   `-moveCursorLeft:` (double-width lines) and ECH (1 report; the others by
   reading): compute in `NSInteger` or clamp the count first; `fix` commit,
   test first (`bugs.md`).
7. `iTermTextDrawingHelper.m:4371` (1): test `cursorRow >= 0` before
   `NSLocationInRange`; `explicit` commit, no behavior change.
8. CHT and CBT (no report; a hang of minutes): cap the count; `fix` commit,
   test first (`bugs.md`).
9. `ExecutionPermits.swift` health check (no report; a rare false crash in
   Development builds and ModernTests): treat `last > now` as just heard from; `fix` commit, test
   first with the injected clock (`bugs.md`).

Not on the list, because the C is intended and the port only has to follow
section 8: 7.3, 7.5, 7.8, 7.10, 7.12, and the intended wraps of section 3.
The hazard at `VT100ScreenMutableState.m:7263` (8.2) needs a test before it
needs a fix.

The stress harness itself, by hand (UNVERIFIED: none of this was run).
What is known: the harness refuses to start while any other iTerm2 runs and
addresses the app by name, so every other instance must be quit first; it
takes the app's path and a `--suite=NAME` option; and
`tools/swift_migration/sanitizer_app.sh` builds a sanitized app at
`tmp/sanitizers/app/Build/Development/iTerm2.app` with the nullability and
integer groups but not the sign-change flags. What is not known: whether
the reports would be collected at all. The harness launches the app with
`open -a`, and whether that passes `UBSAN_OPTIONS` (and so `log_path`) from
the shell to the app was not checked; if it does not, the reports go to
the app's stderr and are lost.
