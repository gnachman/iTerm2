"""Tests for the thread sanitizer grouping and baseline comparison of
tools/swift_migration/sanitizer_summary.py (docs/swift-migration/thread-baseline.md
section 3).

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The fixtures in fixtures/sanitizer_thread:

- tsan.serial-suite: the report file of the serial full-suite thread run of
  2026-11-20 (tmp/sanitizers/runs/thread-20261120-022452/reports/tsan.96268),
  unchanged: two FlagAcrossWritesTests races (VT100Grid currentDate, the
  resolved ledger entry 2.2) and two reports of the Metal completion handler
  race (ledger entry 2.1), all from one process.
- tsan.flag-across-writes-other-build: the report file of a targeted thread
  run of FlagAcrossWritesTests made later that day from another build (other
  offsets, other thread numbers), unchanged.
- tsan.metal: the first Metal report of tsan.serial-suite alone.
- tsan.metal-renumbered: the same report with the compiler's uniquing
  suffixes changed (.448 to .452, .331 to .335) and another pid, as a build
  after an edit of iTermMetalDriver.m would print it. Edited by hand.
- tsan.metal-other-caller: the same report with frame #3 of the previous
  write changed from -[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]
  to -[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:]: a block
  with the same capture layout copied somewhere else. Edited by hand.
- tsan.metal-unsymbolized: the same report with every iTerm2.debug.dylib
  frame printed as the runtime prints a frame it has no name for
  ("<null> <null> (module:arch+offset)"). Edited by hand.

- baseline-2.1.tsv: docs/swift-migration/thread-baseline.tsv with only its
  header and entry 2.1 (entry 2.3 was added to the checked-in file on
  2026-11-22), so the expectations below do not move with the checked-in
  file.

- tsan.kinds: synthetic, written by the first reviewer of the unit: one
  report of each other kind the runtime prints (thread leak,
  lock-order-inversion, heap-use-after-free, signal-unsafe call, destroy of
  a locked mutex), an atomic data race with "As if synchronized via sleep",
  mutex and thread creation stacks and a global location, a data race whose
  previous stack failed to restore and whose location is a stack, and a
  final report cut off before its SUMMARY line.

Every expected value was worked out by hand from the fixture text.
"""

import io
import json
import os
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sanitizer_summary  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures", "sanitizer_thread")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
# The mechanics tests read a fixture holding only entry 2.1, so that adding
# an entry to the checked-in baseline does not change their expectations;
# CheckedInBaselineTests reads the checked-in file.
BASELINE = os.path.join(FIXTURES, "baseline-2.1.tsv")
CHECKED_IN_BASELINE = os.path.join(REPO, "docs", "swift-migration", "thread-baseline.tsv")
ROOT = "/Users/example/iterm2"

METAL_READ = "__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_2"
METAL_WRITE = ("__copy_helper_block_e8_32s40s48b ; -[iTermMetalFrameData measureTimeForStat:ofBlock:]"
               " ; -[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]")


def fixture(name):
    return os.path.join(FIXTURES, name)


def run(*args):
    out = io.StringIO()
    err = io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        status = sanitizer_summary.main(list(args))
    return status, out.getvalue(), err.getvalue()


def run_json(*args, expect=0):
    status, out, err = run("--json", "--root", ROOT, *args)
    assert status == expect, (status, err)
    return json.loads(out)


def keys(groups):
    return [(g["reports"], g["kind"], g["access"], g["previous"], g["location"]) for g in groups]


class FrameNameTests(unittest.TestCase):
    def test_block_invoke_suffix_is_stripped(self):
        n = sanitizer_summary.normalize_function
        self.assertEqual(n(METAL_READ + ".448"), METAL_READ)
        self.assertEqual(n(METAL_READ + ".450"), METAL_READ)
        self.assertEqual(n("__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke.447"),
                         "__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke")
        # Only a block invoke function's suffix: anything else is kept.
        self.assertEqual(n("-[VT100Grid currentDate]"), "-[VT100Grid currentDate]")
        self.assertEqual(n("closure #1 in TokenExecutorImpl.schedule()"),
                         "closure #1 in TokenExecutorImpl.schedule()")
        self.assertEqual(n("version.2"), "version.2")

    def test_frame_parsing(self):
        f = sanitizer_summary.parse_frame(
            "    #5 FakeSession.screenRestore(_:) VT100ScreenTests.swift:2554 (ModernTests:arm64+0x2cf4100)")
        self.assertEqual((f.function, f.module, f.arch, f.offset),
                         ("FakeSession.screenRestore(_:)", "ModernTests", "arm64", "0x2cf4100"))
        f = sanitizer_summary.parse_frame(
            "    #1 closure #1 in XCTAssertEqual<A>(_:_:_:file:line:) <null> (libXCTestSwiftSupport.dylib:arm64e+0x6b9c8)")
        self.assertEqual(f.function, "closure #1 in XCTAssertEqual<A>(_:_:_:file:line:)")
        self.assertEqual(f.module, "libXCTestSwiftSupport.dylib")
        f = sanitizer_summary.parse_frame("    #0 <null> <null> (iTerm2.debug.dylib:arm64+0x1325a10)")
        self.assertIsNone(f.function)
        self.assertEqual(f.module, "iTerm2.debug.dylib")


class GroupingTests(unittest.TestCase):
    def test_serial_suite_groups(self):
        r = run_json(fixture("tsan.serial-suite"))
        groups = r["thread"]["groups"]
        self.assertEqual(keys(groups), [
            (2, "data race", "-[VT100Grid currentDate]", "-[VT100Grid setCurrentDate:]",
             "heap block of size 224"),
            (2, "data race", METAL_READ, METAL_WRITE, "heap block of size 56"),
        ])
        # Both groups come from the one process of the report file.
        self.assertEqual([g["processes"] for g in groups], [1, 1])
        self.assertEqual(groups[0]["tests"], [
            "FlagAcrossWritesTests.testSkinToneWidensNarrowBaseAcrossWrites",
            "FlagAcrossWritesTests.testWriteBoundaryDoesNotChangeResultForVS16",
        ])
        self.assertEqual(groups[1]["tests"], [])
        self.assertEqual(r["unparsed"], 0)

    def test_duplicates_across_files_counted_per_key(self):
        r = run_json(fixture("tsan.serial-suite"), fixture("tsan.flag-across-writes-other-build"),
                     fixture("tsan.metal-renumbered"))
        groups = r["thread"]["groups"]
        # The two builds' VT100Grid reports differ in offsets and thread
        # numbers only: one key, 4 reports from 2 processes. The renumbered
        # Metal report joins the Metal group: 3 reports from 2 processes.
        self.assertEqual([(g["reports"], g["processes"], g["access"]) for g in groups], [
            (4, 2, "-[VT100Grid currentDate]"),
            (3, 2, METAL_READ),
        ])

    def test_console_and_files_count_once(self):
        with tempfile.TemporaryDirectory() as d:
            console = os.path.join(d, "test.log")
            with open(console, "w") as out, open(fixture("tsan.metal")) as src:
                out.write("Test Case '-[A b]' started.\n")
                out.write(src.read())
            r = run_json(fixture("tsan.metal"), "--console", console)
        self.assertEqual([g["reports"] for g in r["thread"]["groups"]], [1])

    def test_text_output_lists_groups(self):
        status, out, _ = run("--root", ROOT, fixture("tsan.serial-suite"))
        self.assertEqual(status, 0)
        self.assertIn("Thread sanitizer reports by kind and top application frames: "
                      "2 group(s), 4 report(s)", out)
        self.assertIn("access:   " + METAL_READ + "\n", out)
        self.assertIn("previous: " + METAL_WRITE + "\n", out)


class BaselineTests(unittest.TestCase):
    def write(self, text):
        f = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_baseline_accepts_metal(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.metal"))
        b = r["baseline"]
        self.assertEqual(b["verdict"], "PASS")
        self.assertEqual([(g["entry"], g["reports"]) for g in b["accepted"]], [("2.1", 1)])
        self.assertEqual(b["new"], [])
        self.assertEqual(b["unmatchable"], [])
        self.assertEqual(b["not_seen"], [])

    def test_renumbered_suffix_matches_same_entry(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.metal-renumbered"))
        self.assertEqual([(g["entry"], g["reports"]) for g in r["baseline"]["accepted"]], [("2.1", 1)])
        self.assertEqual(r["baseline"]["verdict"], "PASS")

    def test_flag_across_writes_is_new_and_fails(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.serial-suite"), expect=1)
        b = r["baseline"]
        self.assertEqual(b["verdict"], "FAIL")
        self.assertEqual(keys(b["new"]), [
            (2, "data race", "-[VT100Grid currentDate]", "-[VT100Grid setCurrentDate:]",
             "heap block of size 224")])
        self.assertEqual([(g["entry"], g["reports"]) for g in b["accepted"]], [("2.1", 2)])

    def test_other_caller_of_same_copy_helper_does_not_match(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.metal-other-caller"), expect=1)
        b = r["baseline"]
        self.assertEqual(b["accepted"], [])
        self.assertEqual([g["previous"] for g in b["new"]], [
            "__copy_helper_block_e8_32s40s48b ; -[iTermMetalFrameData measureTimeForStat:ofBlock:]"
            " ; -[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:]"])
        # The entry did not occur either.
        self.assertEqual([e["entry"] for e in b["not_seen"]], ["2.1"])

    def test_unsymbolized_is_refused(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.metal-unsymbolized"), expect=1)
        b = r["baseline"]
        self.assertEqual(b["accepted"], [])
        self.assertEqual(b["new"], [])
        self.assertEqual(len(b["unmatchable"]), 1)
        self.assertEqual(b["unmatchable"][0]["reports"], 1)
        self.assertIn("frame #0 of the first stack (iTerm2.debug.dylib:arm64+0x1325a10) has no name",
                      b["unmatchable"][0]["unmatchable"])
        status, out, _ = run("--root", ROOT, "--baseline", BASELINE, fixture("tsan.metal-unsymbolized"))
        self.assertEqual(status, 1)
        self.assertIn("Unmatchable (these fail):", out)
        self.assertIn("dsymutil", out)
        self.assertIn("Verdict: FAIL: 0 report(s) outside the baseline, 1 unmatchable; 0 accepted.", out)

    def test_unsymbolized_frame_below_the_key_does_not_matter(self):
        # Frame #4 of the previous write is not one of the frames the key
        # needs: with only it unnamed the report still matches.
        with open(fixture("tsan.metal")) as f:
            text = f.read()
        text = text.replace(
            "    #4 -[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:] <null>",
            "    #4 <null> <null>", 1)
        r = run_json("--baseline", BASELINE, self.write(text))
        self.assertEqual(r["baseline"]["verdict"], "PASS")

    def test_entry_not_seen_is_informational(self):
        status, out, _ = run("--root", ROOT, "--baseline", BASELINE,
                             fixture("tsan.flag-across-writes-other-build"))
        self.assertEqual(status, 1)
        self.assertIn("Baseline entries not seen in this run: 1", out)
        self.assertIn("2.1 (thread-baseline.md section 2.1)", out)
        self.assertIn("remove it from the baseline file and the ledger", out)

    def test_no_reports_passes_and_lists_entry_not_seen(self):
        with tempfile.TemporaryDirectory() as reports:
            status, out, _ = run("--root", ROOT, "--baseline", BASELINE, reports)
        self.assertEqual(status, 0)
        self.assertIn("Verdict: PASS: 0 report(s) outside the baseline, 0 unmatchable; 0 accepted.", out)
        self.assertIn("Baseline entries not seen in this run: 1", out)

    def test_collect_never_fails_on_reports(self):
        status, out, _ = run("--root", ROOT, "--baseline", BASELINE, "--collect", fixture("tsan.serial-suite"))
        self.assertEqual(status, 0)
        self.assertIn("Verdict (--collect, does not fail the run): FAIL: 2 report(s) outside the baseline", out)

    def test_no_tests_still_exits_3(self):
        log = self.write("Test Suite 'Selected tests' started at 2026-11-20 01:08:28.898.\n"
                         "** TEST SUCCEEDED ** [11.714 sec]\n")
        status, _, _ = run("--root", ROOT, "--baseline", BASELINE, "--test-log", log, fixture("tsan.serial-suite"))
        self.assertEqual(status, 3)

    def test_baseline_file_errors(self):
        header = "entry\tkind\taccess\tprevious\tlocation\tledger\n"
        bad = [
            "entry\tkind\taccess\n",
            header + "2.1\tdata race\tf\n",
            header + "2.1\tdata race\tf\tg\t-\tx\n2.1\tdata race\th\tg\t-\tx\n",
            header + "2.1\tdata race\t\tg\t-\tx\n",
            header + "2.1\tdata race\t__1-[A b]_block_invoke.448\tg\t-\tx\n",
        ]
        for text in bad:
            status, _, err = run("--root", ROOT, "--baseline", self.write(text), fixture("tsan.metal"))
            self.assertEqual(status, 2, text)
            self.assertIn("baseline", err)

    def test_location_dash_accepts_any(self):
        text = ("entry\tkind\taccess\tprevious\tlocation\tledger\n"
                "9.9\tdata race\t-[VT100Grid currentDate]\t-[VT100Grid setCurrentDate:]\t-\tx\n")
        r = run_json("--baseline", self.write(text), fixture("tsan.flag-across-writes-other-build"))
        self.assertEqual([(g["entry"], g["reports"]) for g in r["baseline"]["accepted"]], [("9.9", 2)])

    def test_location_must_match_when_given(self):
        text = ("entry\tkind\taccess\tprevious\tlocation\tledger\n"
                "9.9\tdata race\t-[VT100Grid currentDate]\t-[VT100Grid setCurrentDate:]\theap block of size 32\tx\n")
        r = run_json("--baseline", self.write(text), fixture("tsan.flag-across-writes-other-build"), expect=1)
        self.assertEqual(r["baseline"]["accepted"], [])


class CheckedInBaselineTests(unittest.TestCase):
    """The checked-in baseline parses, every entry of it. No report for
    entry 2.3 is committed (its run records are in a lane's tmp/), so only
    parsing is checked here, and that 2.1 still accepts the Metal report."""

    def test_every_entry_parses(self):
        with open(CHECKED_IN_BASELINE) as f:
            data = [line.split("\t", 1)[0] for line in f
                    if line.strip() and not line.startswith("#")]
        self.assertEqual(data[0], "entry")
        entries = sanitizer_summary.read_baseline(CHECKED_IN_BASELINE)
        self.assertEqual([e["entry"] for e in entries], data[1:])
        self.assertIn("2.1", data[1:])

    def test_checked_in_baseline_accepts_metal(self):
        r = run_json("--baseline", CHECKED_IN_BASELINE, fixture("tsan.metal"))
        self.assertEqual(r["baseline"]["verdict"], "PASS")
        self.assertEqual([(g["entry"], g["reports"]) for g in r["baseline"]["accepted"]], [("2.1", 1)])


class KindsTests(unittest.TestCase):
    """Every kind of report is grouped, none is dropped (tsan.kinds)."""

    def test_every_kind_is_grouped(self):
        r = run_json("--baseline", BASELINE, fixture("tsan.kinds"), expect=1)
        self.assertEqual(
            [(g["reports"], g["kind"], g["access"], g["previous"], g["location"]) for g in r["thread"]["groups"]], [
                (1, "data race", "-[Foo atomicSet]", "-[Foo atomicGet]", "global 'gFoo' of size 8"),
                # Cut off before its SUMMARY line: still counted.
                (1, "data race", "-[Foo trunc]", "-", "-"),
                # "[failed to restore the stack]": a previous stack with no
                # frame, which is not the same as no previous stack.
                (1, "data race", "closure #2 in Bar.baz()", "<no application frame>", "stack of thread T*"),
                (1, "destroy of a locked mutex", "-[Foo teardown]", "-", "-"),
                (1, "heap-use-after-free", "-[Foo use]", "-[Foo dealloc]", "-"),
                (1, "lock-order-inversion (potential deadlock)", "-[Foo lockB]", "-", "-"),
                (1, "signal-unsafe call inside of a signal", "handler", "-", "-"),
                (1, "thread leak", "-[Foo start]", "-", "-"),
            ])
        b = r["baseline"]
        self.assertEqual(b["verdict"], "FAIL")
        self.assertEqual(b["line"], "FAIL: 8 report(s) outside the baseline, 0 unmatchable; 0 accepted.")
        self.assertEqual(len(b["new"]), 8)

    def test_report_left_open_at_end_of_file_is_counted(self):
        r = run_json(fixture("tsan.kinds"))
        self.assertIn("-[Foo trunc]", [g["access"] for g in r["thread"]["groups"]])


class ConsoleReportEndTests(unittest.TestCase):
    """A report in a console log with no SUMMARY line ends at the first line
    that is not part of a report (unindented and not a WARNING), so the
    xcodebuild lines after it are not taken as sections of it."""

    def write(self, text):
        f = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_unindented_line_ends_the_report(self):
        log = self.write(
            "WARNING: ThreadSanitizer: data race (pid=7)\n"
            "  Write of size 8 at 0x0003 by thread T6:\n"
            "    #0 -[Foo trunc] <null> (iTerm2.debug.dylib:arm64+0xe0)\n"
            "Test Case '-[A b]' passed (0.001 seconds).\n"
            "  Previous write of size 8 at 0x0003 by main thread:\n"
            "    #0 -[Foo later] <null> (iTerm2.debug.dylib:arm64+0xe4)\n"
            "  Location is global 'gLater' at 0x10\n")
        r = run_json("--console", log)
        self.assertEqual([(g["access"], g["previous"], g["location"]) for g in r["thread"]["groups"]],
                         [("-[Foo trunc]", "-", "-")])


class AppModuleTests(unittest.TestCase):
    def test_first_party_frameworks_are_application_frames(self):
        for module in ("BetterFontPicker", "ColorPicker", "SearchableComboListView", "iTerm2ImportStatus"):
            text = ("WARNING: ThreadSanitizer: data race (pid=1)\n"
                    "  Write of size 8 at 0x1 by thread T1:\n"
                    "    #0 -[Picker set] <null> (%s:arm64+0x10)\n"
                    "    #1 -[Foo caller] <null> (iTerm2.debug.dylib:arm64+0x20)\n"
                    "SUMMARY: ThreadSanitizer: data race (%s:arm64+0x10) in -[Picker set]\n" % (module, module))
            f = tempfile.NamedTemporaryFile("w", suffix=".tsan", delete=False)
            f.write(text)
            f.close()
            self.addCleanup(os.unlink, f.name)
            r = run_json(f.name)
            self.assertEqual(r["thread"]["groups"][0]["access"], "-[Picker set]", module)


class SymbolizeTests(unittest.TestCase):
    """--symbolize with a stand-in for atos (--atos), since the binaries the
    collection's reports came from have been rebuilt since."""

    def make(self, atos_lines):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        build = os.path.join(d.name, "Build", "iTerm2.app", "Contents", "MacOS")
        os.makedirs(build)
        open(os.path.join(build, "iTerm2.debug.dylib"), "w").close()
        table = os.path.join(d.name, "table")
        with open(table, "w") as f:
            f.write("".join("%s %s\n" % kv for kv in atos_lines.items()))
        atos = os.path.join(d.name, "atos")
        with open(atos, "w") as f:
            f.write("#!/bin/sh\n"
                    "# Prints the line of the table for each address argument\n"
                    "# (atos -o BINARY -l 0x0 [-arch ARCH] ADDRESS ...).\n"
                    "skip=0; for a in \"$@\"; do if [ $skip = 1 ]; then skip=0; continue; fi; "
                    "case \"$a\" in -o|-l|-arch) skip=1;; 0x*) "
                    "line=$(grep \"^$a \" '%s' | cut -d' ' -f2-); "
                    "if [ -n \"$line\" ]; then echo \"$line\"; else echo \"$a\"; fi;; esac; done\n" % table)
        os.chmod(atos, os.stat(atos).st_mode | stat.S_IXUSR)
        return os.path.join(d.name, "Build"), atos

    NAMES = {
        "0x1325a10": "__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke_2.448 (in iTerm2.debug.dylib) + 88",
        "0xaea100": "__copy_helper_block_e8_32s40s48b (in iTerm2.debug.dylib) + 20",
        "0xbcc6f4": "-[iTermMetalFrameData measureTimeForStat:ofBlock:] (in iTerm2.debug.dylib) + 136",
        "0x132475c": "-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:] (in iTerm2.debug.dylib) + 400",
        "0x1310970": "-[iTermMetalDriver enqueueDrawCallsForFrameData:commandBuffer:] (in iTerm2.debug.dylib) + 12",
    }

    def test_symbolize_names_frames_and_matches(self):
        build, atos = self.make(self.NAMES)
        r = run_json("--baseline", BASELINE, "--symbolize", build, "--atos", atos,
                     fixture("tsan.metal-unsymbolized"))
        self.assertEqual(r["baseline"]["verdict"], "PASS")
        # 10 frames have one of the five offsets: frame #0 of the read,
        # #0, #2, #3, #4 and #6 of the previous write, #2, #3, #4 and #6 of
        # the allocation.
        self.assertEqual(r["symbolize"]["named"], 10)
        self.assertEqual(r["symbolize"]["unverified"], ["iTerm2.debug.dylib"])
        self.assertEqual(r["symbolize"]["checked"], 0)
        self.assertIsNone(r["symbolize"]["refused"])

    def test_symbolize_says_how_many_named_frames_it_checked(self):
        build, atos = self.make(self.NAMES)
        status, out, _ = run("--root", ROOT, "--symbolize", build, "--atos", atos, fixture("tsan.metal"))
        self.assertEqual(status, 0)
        # The report names 17 frames in iTerm2.debug.dylib (1 + 8 + 8) with
        # one of the five offsets 10 times (the other 7 offsets atos cannot
        # name, so they are not checked).
        self.assertIn("Symbolized 0 frame(s) and checked 10 named frame(s) with atos", out)

    def test_dsym_copy_is_not_a_second_binary(self):
        build, atos = self.make(self.NAMES)
        dwarf = os.path.join(build, "iTerm2.debug.dylib.dSYM", "Contents", "Resources", "DWARF")
        os.makedirs(dwarf)
        open(os.path.join(dwarf, "iTerm2.debug.dylib"), "w").write("different size")
        r = run_json("--baseline", BASELINE, "--symbolize", build, "--atos", atos,
                     fixture("tsan.metal-unsymbolized"))
        self.assertIsNone(r["symbolize"]["refused"])
        self.assertEqual(r["baseline"]["verdict"], "PASS")

    def test_symbolize_refuses_a_binary_that_disagrees(self):
        # Cross-check: for the named frames of the report the binary must
        # give the same names. A rebuilt binary does not (on 2026-11-20 atos
        # on the main checkout's rebuilt thread build gave
        # __45-[iTermCommandRunner didReadData:completion:]_block_invoke at the
        # copy helper's offset).
        names = dict(self.NAMES)
        names["0x1325a10"] = ("__61-[iTermMetalDriver finishDrawingWithCommandBuffer:frameData:]_block_invoke.447"
                              " (in iTerm2.debug.dylib) + 140")
        names["0xaea100"] = "__45-[iTermCommandRunner didReadData:completion:]_block_invoke (in iTerm2.debug.dylib) + 112"
        build, atos = self.make(names)
        status, out, _ = run("--root", ROOT, "--baseline", BASELINE, "--symbolize", build, "--atos", atos,
                             fixture("tsan.metal"))
        # The report was already named, so it still matches; the
        # symbolization is refused and says why.
        self.assertEqual(status, 0)
        self.assertIn("Symbolization refused", out)
        self.assertIn("not the binary that ran", out)
        build, atos = self.make(names)
        r = run_json("--baseline", BASELINE, "--symbolize", build, "--atos", atos,
                     fixture("tsan.serial-suite"), fixture("tsan.metal-unsymbolized"), expect=1)
        self.assertIn("not the binary that ran", r["symbolize"]["refused"])
        self.assertEqual(len(r["baseline"]["unmatchable"]), 1)

    def test_symbolize_without_binary_says_so(self):
        with tempfile.TemporaryDirectory() as empty:
            status, out, _ = run("--root", ROOT, "--baseline", BASELINE, "--symbolize", empty,
                                 "--atos", "/bin/false", fixture("tsan.metal-unsymbolized"))
        self.assertEqual(status, 1)
        self.assertIn("no file named iTerm2.debug.dylib under", out)


if __name__ == "__main__":
    unittest.main()
