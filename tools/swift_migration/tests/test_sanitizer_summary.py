"""Tests for tools/swift_migration/sanitizer_summary.py.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The fixtures in fixtures/sanitizer_summary come from the runs that proved
tools/swift_migration/sanitizer_tests.sh on 2026-11-20, with the checkout's
path replaced by /Users/example/iterm2 and every stack cut to its first four
frames:

- ubsan.probe-integer: the integer mode on ModernTests/SanitizerProbeTests
  (one implicit truncation, one signed overflow, both in ModernTests).
- ubsan.vt100screen-integer: the integer mode on ModernTests/VT100ScreenTests
  (three implicit truncations in sources/).
- ubsan.launch-nullability: the nullability mode with --collect on
  SanitizerProbeTests (eight reports in sources/ from the test host's
  launch, one from the probe in ModernTests).
- tsan.probe-thread: the thread mode on the probe (one data race; the
  ThreadSanitizer runtime prints base names, not paths).
- nullability-halt-console.log: an excerpt of the test.log of the aborting
  nullability mode, with the report among xcodebuild's own output.
- nullability-launch-colored.log: an excerpt of a console log whose report
  still has the runtime's color escapes, between five lines of app logging
  and one of xcodebuild's.

The fixtures in fixtures/sanitizer_nullability_real are four report files of
an interrupted aborting nullability run of 2026-11-23, with the checkout's
path replaced by /Users/example/iterm2 and every stack cut to its first four
frames: a nil passed to an NSString.h method, one passed to a method
declared in the generated iTerm2SharedARC-Swift.h, a nil return, and
ubsan.44108, cut off after its note line when the host was killed.

Every expected value below was worked out by hand from the fixture text.
Edge cases with no real example are written in a temporary directory.
"""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sanitizer_summary  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures", "sanitizer_summary")
ROOT = "/Users/example/iterm2"


def fixture(name):
    return os.path.join(FIXTURES, name)


def run(*args):
    """Runs the script's main with args; returns (exit status, stdout)."""
    out = io.StringIO()
    err = io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        status = sanitizer_summary.main(list(args))
    return status, out.getvalue(), err.getvalue()


def run_json(*args):
    status, out, _ = run("--json", *args)
    assert status == 0, status
    return json.loads(out)


def locations(group):
    return [(row["count"], row["kind"], row["location"]) for row in group["top"]]


class FixtureTests(unittest.TestCase):
    def test_integer_probe(self):
        r = run_json("--root", ROOT, fixture("ubsan.probe-integer"))
        self.assertEqual(r["files"], 1)
        self.assertEqual(r["lines"], 14)
        self.assertEqual(r["reports"], 2)
        self.assertEqual(r["in_scope"]["reports"], 0)
        self.assertEqual(r["other"]["reports"], 2)
        self.assertEqual(locations(r["other"]), [
            (1, "implicit-signed-integer-truncation", "ModernTests/SanitizerProbeTests.m:88:22"),
            (1, "signed-integer-overflow", "ModernTests/SanitizerProbeTests.m:79:11"),
        ])
        self.assertEqual(r["other"]["top"][1]["message"],
                         "signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'")
        self.assertEqual(r["unparsed"], 0)

    def test_integer_in_scope(self):
        r = run_json("--root", ROOT, fixture("ubsan.vt100screen-integer"))
        self.assertEqual(r["in_scope"]["reports"], 3)
        self.assertEqual(r["other"]["reports"], 0)
        self.assertEqual(r["in_scope"]["by_kind"],
                         [{"kind": "implicit-signed-integer-truncation", "count": 3}])
        self.assertEqual([row["location"] for row in r["in_scope"]["top"]], [
            "sources/ScreenChar/ScreenChar.m:421:16",
            "sources/VT100/VT100Grid.m:2556:22",
            "sources/VT100/VT100Grid.m:2609:22",
        ])
        self.assertEqual(r["unparsed"], 0)

    def test_nullability_launch_reports(self):
        r = run_json("--root", ROOT, fixture("ubsan.launch-nullability"))
        self.assertEqual(r["reports"], 9)
        self.assertEqual(r["in_scope"]["reports"], 8)
        self.assertEqual(r["in_scope"]["locations"], 8)
        self.assertEqual(r["in_scope"]["by_kind"], [
            {"kind": "invalid-null-argument", "count": 7},
            {"kind": "invalid-null-return", "count": 1},
        ])
        self.assertEqual(locations(r["other"]),
                         [(1, "invalid-null-argument", "ModernTests/SanitizerProbeTests.m:72:5")])
        self.assertEqual(r["unparsed"], 0)

    def test_top_limits_each_group(self):
        r = run_json("--root", ROOT, "--top", "3", fixture("ubsan.launch-nullability"))
        self.assertEqual(len(r["in_scope"]["top"]), 3)
        self.assertEqual(r["in_scope"]["locations"], 8)
        # Equal counts sort by kind, then location.
        self.assertEqual(r["in_scope"]["top"][0]["location"], "sources/API/iTermScriptsMenuController.m:610:38")

    def test_thread_report_outside_any_index(self):
        # The root does not exist, so the base name matches nothing: other.
        r = run_json("--root", ROOT, fixture("tsan.probe-thread"))
        self.assertEqual(r["reports"], 1)
        self.assertEqual(locations(r["other"]), [(1, "data race", "SanitizerProbeTests.m:103")])
        self.assertEqual(r["other"]["top"][0]["message"], "Write of size 4 at 0x... by main thread:")
        self.assertEqual(r["unparsed"], 0)

    def test_thread_base_name_is_resolved_under_root(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "ModernTests"))
            open(os.path.join(root, "ModernTests", "SanitizerProbeTests.m"), "w").close()
            r = run_json("--root", root, fixture("tsan.probe-thread"))
        self.assertEqual(locations(r["other"]), [(1, "data race", "ModernTests/SanitizerProbeTests.m:103")])

    def test_halting_console_log_mixed(self):
        r = run_json("--root", ROOT, "--mixed", fixture("nullability-halt-console.log"))
        self.assertEqual(r["lines"], 78)
        self.assertEqual(r["reports"], 1)
        self.assertEqual(locations(r["other"]),
                         [(1, "invalid-null-argument", "ModernTests/SanitizerProbeTests.m:72:5")])
        # 78 lines: the report is lines 11 to 18 (error, note, four frames,
        # a blank line, SUMMARY); 5 more lines are blank. The other 65 are
        # xcodebuild's.
        self.assertEqual(r["other_text"], 65)
        self.assertEqual(r["unparsed"], 0)

    def test_console_log_without_mixed_shows_unparsed(self):
        r = run_json("--root", ROOT, fixture("nullability-halt-console.log"))
        self.assertEqual(r["reports"], 1)
        self.assertEqual(r["unparsed"], 65)
        self.assertEqual(len(r["unparsed_shown"]), 20)
        self.assertEqual(r["unparsed_shown"][0]["line"], 1)
        self.assertTrue(r["unparsed_shown"][0]["text"].startswith("Test Suite 'Selected tests' started"))

    def test_color_escapes_are_removed(self):
        r = run_json("--root", ROOT, fixture("nullability-launch-colored.log"))
        self.assertEqual(r["reports"], 1)
        self.assertEqual(locations(r["in_scope"]),
                         [(1, "invalid-null-argument", "sources/Language/iTermVariables.m:422:103")])
        self.assertEqual(r["in_scope"]["top"][0]["message"],
                         "null pointer passed as argument 1, which is declared to never be null")
        # 14 lines: five of app logging, the report (eight lines), and one
        # line of xcodebuild's after it.
        self.assertEqual(r["unparsed"], 6)

    def test_directory_reads_every_file(self):
        r = run_json("--root", ROOT, FIXTURES)
        self.assertEqual(r["files"], 6)
        # 2 + 3 + 9 + 1 + 1 + 1
        self.assertEqual(r["reports"], 17)

    def test_text_output(self):
        status, out, _ = run("--root", ROOT, fixture("ubsan.vt100screen-integer"))
        self.assertEqual(status, 0)
        self.assertIn("Reports: 3 at 3 location(s): 3 in scope, 0 in other code.", out)
        self.assertIn("     3  implicit-signed-integer-truncation\n", out)
        self.assertIn("     1  implicit-signed-integer-truncation  sources/VT100/VT100Grid.m:2556:22\n", out)
        self.assertIn("Unparsed lines: 0", out)


class EdgeCaseTests(unittest.TestCase):
    def write(self, text):
        f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_report_without_summary_or_error_type(self):
        path = self.write(
            "/r/sources/A.m:1:2: runtime error: shift exponent 40 is too large\n"
            "/r/sources/A.m:3:4: runtime error: division by zero\n"
            "SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior /r/sources/A.m:3:4 in \n")
        r = run_json("--root", "/r", path)
        self.assertEqual(r["in_scope"]["by_kind"], [{"kind": "undefined-behavior", "count": 2}])
        self.assertEqual(r["unparsed"], 0)

    def test_thread_report_without_summary(self):
        path = self.write(
            "==================\n"
            "WARNING: ThreadSanitizer: heap-use-after-free (pid=7)\n"
            "  Read of size 8 at 0x1234 by thread T1:\n")
        r = run_json("--root", "/r", path)
        self.assertEqual(locations(r["other"]), [(1, "heap-use-after-free", "<unknown>")])
        self.assertEqual(r["other"]["top"][0]["message"], "Read of size 8 at 0x... by thread T1:")

    def test_unknown_lines_are_counted_and_shown(self):
        path = self.write(
            "==123==WARNING: a runtime notice\n"
            "something unexpected\n"
            "/r/sources/A.m:1:2: runtime error: signed integer overflow\n"
            "    #0 0x1 in f A.m:1\n"
            "an unexpected line inside a report\n"
            "SUMMARY: UndefinedBehaviorSanitizer: signed-integer-overflow /r/sources/A.m:1:2 in \n"
            "SUMMARY: ThreadSanitizer: data race A.m:1 in f\n")
        r = run_json("--root", "/r", path)
        self.assertEqual(r["reports"], 1)
        self.assertEqual(r["unparsed"], 3)
        self.assertEqual([(row["line"], row["text"]) for row in r["unparsed_shown"]], [
            (2, "something unexpected"),
            (5, "an unexpected line inside a report"),
            (7, "SUMMARY: ThreadSanitizer: data race A.m:1 in f"),
        ])

    def test_ambiguous_base_name(self):
        with tempfile.TemporaryDirectory() as root:
            for d in ("sources", "ModernTests", "sources/Sub"):
                os.makedirs(os.path.join(root, d), exist_ok=True)
            for rel in ("sources/A.m", "ModernTests/A.m", "sources/B.m", "sources/Sub/B.m"):
                open(os.path.join(root, rel), "w").close()
            path = self.write(
                "WARNING: ThreadSanitizer: data race (pid=1)\n"
                "SUMMARY: ThreadSanitizer: data race A.m:5 in f\n"
                "WARNING: ThreadSanitizer: data race (pid=1)\n"
                "SUMMARY: ThreadSanitizer: data race B.m:6 in g\n")
            r = run_json("--root", root, path)
        # A.m is in sources/ and in ModernTests/: not all in scope, so other.
        self.assertEqual(locations(r["other"]),
                         [(1, "data race", "A.m:5 (ambiguous: 2 files have this name)")])
        # Both B.m files are in sources/: in scope.
        self.assertEqual(locations(r["in_scope"]),
                         [(1, "data race", "B.m:6 (ambiguous: 2 files have this name)")])

    def test_scope_prefixes(self):
        lines = []
        for rel in ("sources/a.m", "ThirdParty/PSMTabBarControl/b.m", "ThirdParty/fmdb/c.m",
                    "SignedArchive/d.m", "pidinfo/e.m", "iTerm2SandboxedWorker/f.m",
                    "ShellLauncher/g.c", "ColorPicker/h.m", "SearchableComboListView/i.m",
                    "BetterFontPicker/j.m", "submodules/k.m", "ModernTests/l.m"):
            lines.append("/r/%s:1:1: runtime error: x\n" % rel)
        lines.append("/elsewhere/sources/m.m:1:1: runtime error: x\n")
        lines.append("<unknown>: runtime error: x\n")
        r = run_json("--root", "/r", self.write("".join(lines)))
        self.assertEqual(r["in_scope"]["reports"], 9)
        self.assertEqual(sorted(row["location"] for row in r["other"]["top"]), [
            "/elsewhere/sources/m.m:1:1",
            "<unknown>",
            "ModernTests/l.m:1:1",
            "ThirdParty/fmdb/c.m:1:1",
            "submodules/k.m:1:1",
        ])

    def test_interleaved_reports_take_only_their_own_summary(self):
        # Two processes writing to one console: B's report line arrives
        # before A's SUMMARY. A's SUMMARY is not the open report's, so it is
        # unparsed and A keeps the default kind; B gets its own.
        path = self.write(
            "/r/sources/A.m:1:1: runtime error: first\n"
            "/r/sources/B.m:2:2: runtime error: second\n"
            "SUMMARY: UndefinedBehaviorSanitizer: signed-integer-overflow /r/sources/A.m:1:1 \n"
            "SUMMARY: UndefinedBehaviorSanitizer: invalid-null-argument /r/sources/B.m:2:2 \n"
            "SUMMARY: UndefinedBehaviorSanitizer: shift-exponent /r/sources/C.m:3:3 \n")
        r = run_json("--root", "/r", path)
        self.assertEqual(sorted(locations(r["in_scope"])), [
            (1, "invalid-null-argument", "sources/B.m:2:2"),
            (1, "undefined-behavior", "sources/A.m:1:1"),
        ])
        self.assertEqual(r["unparsed"], 2)
        self.assertEqual([row["line"] for row in r["unparsed_shown"]], [3, 5])
        # In a console log too: SUMMARY lines are sanitizer output.
        r = run_json("--root", "/r", "--mixed", path)
        self.assertEqual(r["unparsed"], 2)
        self.assertEqual(r["other_text"], 0)

    def test_summary_kind_does_not_cross_to_a_later_report(self):
        path = self.write(
            "/r/sources/A.m:1:1: runtime error: first\n"
            "SUMMARY: UndefinedBehaviorSanitizer: shift-base /r/sources/Z.m:9:9 \n"
            "SUMMARY: UndefinedBehaviorSanitizer: shift-exponent /r/sources/A.m:1:1 \n")
        r = run_json("--root", "/r", path)
        self.assertEqual(locations(r["in_scope"]), [(1, "shift-exponent", "sources/A.m:1:1")])
        self.assertEqual(r["unparsed"], 1)

    def test_console_and_files_count_a_report_once(self):
        report = ("/r/sources/A.m:1:1: runtime error: x\n"
                  "SUMMARY: UndefinedBehaviorSanitizer: invalid-null-argument /r/sources/A.m:1:1 \n")
        with tempfile.TemporaryDirectory() as reports:
            for name in ("ubsan.1", "ubsan.2"):
                with open(os.path.join(reports, name), "w") as f:
                    f.write(report)
            console = self.write(
                "Test Case '-[T t]' started.\n" + report +
                "/r/sources/B.m:2:2: runtime error: y\n"
                "SUMMARY: UndefinedBehaviorSanitizer: invalid-null-return /r/sources/B.m:2:2 \n")
            r = run_json("--root", "/r", reports, "--console", console)
        # A.m: twice in files, once in the console: 2. B.m: console only: 1.
        self.assertEqual(sorted(locations(r["in_scope"])), [
            (1, "invalid-null-return", "sources/B.m:2:2"),
            (2, "invalid-null-argument", "sources/A.m:1:1"),
        ])
        self.assertEqual(r["reports"], 3)
        self.assertEqual(r["console_only"], 1)
        self.assertEqual(r["in_both"], 1)
        self.assertEqual(r["other_text"], 1)
        self.assertEqual(r["unparsed"], 0)

    def test_console_only(self):
        r = run_json("--root", ROOT, "--console", fixture("nullability-halt-console.log"))
        self.assertEqual(r["reports"], 1)
        self.assertEqual(r["console_only"], 1)
        self.assertEqual(r["other_text"], 65)

    def test_truncation_says_what_is_not_shown(self):
        status, out, _ = run("--root", ROOT, "--top", "3", fixture("ubsan.launch-nullability"))
        self.assertEqual(status, 0)
        self.assertIn("... 5 more location(s) not shown; run sanitizer_summary.py again with --top 8,", out)
        self.assertIn("UBSan reports each source location\nonce per process", out)
        r = run_json("--root", ROOT, "--top", "3", fixture("ubsan.launch-nullability"))
        self.assertEqual(r["in_scope"]["not_shown"], 5)
        self.assertEqual(len(r["in_scope"]["all"]), 8)
        self.assertEqual(r["in_scope"]["all"][:3], r["in_scope"]["top"])

    def test_tests_executed_serial_with_crash(self):
        log = self.write(
            "Test Case '-[SanitizerProbeTests testA]' started.\n"
            "Test Case '-[SanitizerProbeTests testA]' skipped (0.003 seconds).\n"
            "Test Case '-[SanitizerProbeTests testB]' started.\n"
            "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.\n"
            "Test Case '-[SanitizerProbeTests testC]' started.\n"
            "Test Case '-[SanitizerProbeTests testC]' passed (0.003 seconds).\n"
            "\t Executed 1 test, with 0 failures (0 unexpected) in 0.003 (0.004) seconds\n")
        status, out, _ = run("--root", "/r", "--console", log, "--test-log", log)
        self.assertEqual(status, 0)
        self.assertIn("Tests executed: 3 (passed 1, failed 0, skipped 1, started with no result 1)", out)

    def test_tests_executed_parallel(self):
        log = self.write(
            "Testing started\n"
            "Test suite 'SanitizerProbeTests' started on 'My Mac - iTerm2 (1)'\n"
            "Test case '-[SanitizerProbeTests testA]' skipped on 'My Mac - iTerm2 (1)' (0.003 seconds)\n"
            "Test case '-[SanitizerProbeTests testB]' failed on 'My Mac - iTerm2 (1)' (0.000 seconds)\n"
            "Test case '-[SanitizerProbeTests testC]' skipped on 'My Mac - iTerm2 (2)' (0.003 seconds)\n")
        r = run_json("--root", "/r", "--console", log, "--test-log", log)
        self.assertEqual(r["tests"]["executed"], 3)
        self.assertEqual(r["tests"]["skipped"], 2)
        self.assertEqual(r["tests"]["failed"], 1)

    def test_no_tests_executed_exits_3(self):
        log = self.write(
            "Test Suite 'Selected tests' started at 2026-11-20 01:08:28.898.\n"
            "Test Suite 'ModernTests.xctest' started at 2026-11-20 01:08:28.899.\n"
            "Test Suite 'ModernTests.xctest' passed at 2026-11-20 01:08:28.899.\n"
            "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds\n"
            "** TEST SUCCEEDED ** [11.714 sec]\n")
        status, out, _ = run("--root", "/r", "--console", log, "--test-log", log)
        self.assertEqual(status, 3)
        self.assertIn("Tests executed: 0 ", out)
        self.assertIn("error: the run executed no tests", out)

    def test_missing_file_is_an_error(self):
        status, _, err = run("/nonexistent/sanitizer/report")
        self.assertEqual(status, 2)
        self.assertIn("cannot read", err)


SIGN_FIXTURES = os.path.join(HERE, "fixtures", "sanitizer_sign")


class SignChangeTests(unittest.TestCase):
    """The integer-sign mode of sanitizer_tests.sh, and the function of each
    location.

    fixtures/sanitizer_sign/ubsan.probe-integer-sign holds the two report
    files written on 2026-11-20 by two probes compiled with Xcode's clang
    (Apple clang 21) and the integer-sign mode's flags (the integer group
    plus -Xclang -fsanitize=implicit-integer-sign-change and its recover
    flag), run with the mode's UBSAN_OPTIONS: an Objective-C file with ARC
    and Foundation, compiled with -g so its frames carry file and line, and
    an Objective-C++ file. The probes were under a sources/ directory; the
    path up to it is replaced by /Users/example/iterm2. It is in a directory
    of its own so the directory count of FixtureTests is unchanged."""

    def write(self, text):
        f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
        f.write(text)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_sign_change_kinds(self):
        r = run_json("--root", ROOT, os.path.join(SIGN_FIXTURES, "ubsan.probe-integer-sign"))
        self.assertEqual(r["reports"], 4)
        self.assertEqual(r["in_scope"]["reports"], 4)
        self.assertEqual(r["in_scope"]["by_kind"], [
            {"kind": "implicit-integer-sign-change", "count": 2},
            {"kind": "implicit-signed-integer-truncation", "count": 1},
            {"kind": "implicit-signed-integer-truncation-or-sign-change", "count": 1},
        ])
        self.assertEqual(locations(r["in_scope"]), [
            (1, "implicit-integer-sign-change", "sources/Probe/SignProbe.m:6:41"),
            (1, "implicit-integer-sign-change", "sources/Probe/SignProbeCxx.mm:2:73"),
            (1, "implicit-signed-integer-truncation", "sources/Probe/SignProbe.m:14:29"),
            (1, "implicit-signed-integer-truncation-or-sign-change", "sources/Probe/SignProbe.m:11:17"),
        ])
        self.assertEqual(r["in_scope"]["top"][0]["message"],
                         "implicit conversion from type 'NSInteger' (aka 'long') of value -1 (64-bit, signed) "
                         "to type 'NSUInteger' (aka 'unsigned long') changed the value to "
                         "18446744073709551615 (64-bit, unsigned)")
        self.assertEqual(r["unparsed"], 0)

    def test_function_from_symbolized_frame(self):
        r = run_json("--root", ROOT, os.path.join(SIGN_FIXTURES, "ubsan.probe-integer-sign"))
        functions = {row["location"]: row["function"] for row in r["in_scope"]["all"]}
        self.assertEqual(functions, {
            "sources/Probe/SignProbe.m:6:41": "-[P idx:]",
            "sources/Probe/SignProbeCxx.mm:2:73": "main",
            "sources/Probe/SignProbe.m:14:29": "main",
            "sources/Probe/SignProbe.m:11:17": "main",
        })

    def test_function_from_module_offset_frame(self):
        r = run_json("--root", ROOT, fixture("ubsan.vt100screen-integer"))
        functions = {row["location"]: row["function"] for row in r["in_scope"]["all"]}
        self.assertEqual(functions, {
            "sources/ScreenChar/ScreenChar.m:421:16": "CharArrayToString",
            "sources/VT100/VT100Grid.m:2556:22": "-[VT100Grid compactLineDump]",
            "sources/VT100/VT100Grid.m:2609:22": "-[VT100Grid compactLineDumpWithContinuationMarks]",
        })

    def test_function_edge_cases(self):
        cases = [
            ("    #0 0x0001 in iTermFoo::bar(int, long)+0x24 (iTerm2.debug.dylib:arm64+0x10)",
             "iTermFoo::bar(int, long)"),
            ("    #0 0x0001 in VT100ScreenTests.testX() VT100ScreenTests.swift:632", "VT100ScreenTests.testX()"),
            ("    #0 0x0001 in @objc Foo.bar() /<compiler-generated>", "@objc Foo.bar()"),
            ("    #0 0x0001 in +[iTermFoo bar:baz:]+0x8 (iTerm2.debug.dylib:arm64+0x10)", "+[iTermFoo bar:baz:]"),
            ("    #0 0x0001  (<unknown module>)", "<unknown>"),
        ]
        for frame, expected in cases:
            with self.subTest(frame=frame):
                path = self.write(
                    "/r/sources/A.m:1:2: runtime error: x\n" + frame + "\n\n"
                    "SUMMARY: UndefinedBehaviorSanitizer: implicit-integer-sign-change /r/sources/A.m:1:2 \n")
                r = run_json("--root", "/r", path)
                self.assertEqual(r["in_scope"]["all"][0]["function"], expected)
                self.assertEqual(r["unparsed"], 0)

    def test_report_without_frames_has_unknown_function(self):
        path = self.write(
            "/r/sources/A.m:1:2: runtime error: x\n"
            "SUMMARY: UndefinedBehaviorSanitizer: implicit-integer-sign-change /r/sources/A.m:1:2 \n")
        r = run_json("--root", "/r", path)
        self.assertEqual(r["in_scope"]["all"][0]["function"], "<unknown>")

    def test_only_the_first_frame_names_the_function(self):
        path = self.write(
            "/r/sources/A.m:1:2: runtime error: x\n"
            "    #0 0x0001 in first+0x4 (iTerm2.debug.dylib:arm64+0x10)\n"
            "    #1 0x0002 in second+0x4 (iTerm2.debug.dylib:arm64+0x20)\n"
            "\n"
            "SUMMARY: UndefinedBehaviorSanitizer: implicit-integer-sign-change /r/sources/A.m:1:2 \n")
        r = run_json("--root", "/r", path)
        self.assertEqual(r["in_scope"]["all"][0]["function"], "first")

    def test_text_output_names_the_function(self):
        status, out, _ = run("--root", ROOT, fixture("ubsan.vt100screen-integer"))
        self.assertEqual(status, 0)
        self.assertIn("      in -[VT100Grid compactLineDump]\n", out)


class FailOnReportsTests(unittest.TestCase):
    """--fail-on-reports: the verdict of the non-aborting nullability mode.
    Every UBSan report fails (the runtime has already hidden the suppressed
    ones), each listed with the tests it came from: a test named on any of
    its stack frames, or in the report file's name
    (ubsan.<Class>.<method>.<pid>, as a per-test report path would make it)."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def write(self, name, text):
        path = os.path.join(self.dir.name, name)
        with open(path, "w") as f:
            f.write(text)
        return path

    @staticmethod
    def report(location, frames, kind="invalid-null-argument"):
        lines = ["%s: runtime error: null pointer passed as argument 1, which is declared to never be null" % location]
        lines += ["    #%d 0x000100000000 in %s" % (i, f) for i, f in enumerate(frames)]
        lines += ["", "SUMMARY: UndefinedBehaviorSanitizer: %s %s " % (kind, location)]
        return "\n".join(lines) + "\n"

    def test_reports_fail_with_the_tests_they_came_from(self):
        status, out, _ = run("--root", ROOT, "--fail-on-reports", fixture("ubsan.launch-nullability"))
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 9 report(s) at 9 location(s) that no suppression hides.", out)
        self.assertIn("tests:    SanitizerProbeTests.testNullabilityProbe", out)
        # The launch's reports have no test on their frames.
        self.assertIn("tests:    none identified", out)

    def test_json_groups(self):
        status, out, _ = run("--json", "--root", ROOT, "--fail-on-reports", fixture("ubsan.launch-nullability"))
        self.assertEqual(status, 1)
        v = json.loads(out)["fail_on_reports"]
        self.assertEqual(v["verdict"], "FAIL")
        probe = [g for g in v["groups"] if g["location"] == "ModernTests/SanitizerProbeTests.m:72:5"]
        self.assertEqual(len(probe), 1)
        self.assertEqual(probe[0]["tests"], ["SanitizerProbeTests.testNullabilityProbe"])
        self.assertEqual(len(v["groups"]), 9)

    def test_no_reports_pass(self):
        path = self.write("ubsan.77", "")
        status, out, _ = run("--root", "/r", "--fail-on-reports", path)
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict: PASS: no report outside the suppressions.", out)

    def test_collect_prints_the_verdict_without_failing(self):
        status, out, _ = run("--root", ROOT, "--fail-on-reports", "--collect", fixture("ubsan.launch-nullability"))
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict (--collect, does not fail the run): FAIL: 9 report(s)", out)

    def test_collect_alone_is_still_a_usage_error(self):
        with self.assertRaises(SystemExit) as cm:
            run("--root", "/r", "--collect", self.write("x", ""))
        self.assertEqual(cm.exception.code, 2)

    def test_test_and_pid_from_the_file_name(self):
        self.write("ubsan.FooTests.testBar.123", self.report("/r/sources/A.m:1:2", ["-[A b]+0x10 (iTerm2.debug.dylib:arm64+0x10)"]))
        self.write("ubsan.456", self.report("/r/sources/B.m:3:4", ["-[B c] B.m:3"]))
        status, out, _ = run("--json", "--root", "/r", "--fail-on-reports", self.dir.name)
        self.assertEqual(status, 1)
        groups = {g["location"]: g for g in json.loads(out)["fail_on_reports"]["groups"]}
        self.assertEqual(groups["sources/A.m:1:2"]["tests"], ["FooTests.testBar"])
        self.assertEqual(groups["sources/A.m:1:2"]["pids"], ["123"])
        self.assertEqual(groups["sources/B.m:3:4"]["tests"], [])
        self.assertEqual(groups["sources/B.m:3:4"]["pids"], ["456"])

    def test_a_report_file_that_does_not_parse_fails(self):
        # A host killed while writing leaves a truncated file; the verdict
        # depends on parsing, so such a file fails the run and is named.
        path = self.write("ubsan.321", "garbage line one\n#0 half a fra")
        status, out, _ = run("--root", "/r", "--fail-on-reports", path)
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 0 report(s) at 0 location(s) that no suppression hides; "
                      "1 report file(s) with lines that are not a report.", out)
        self.assertIn("not a report: %s (2 line(s))" % path, out)
        status, _, _ = run("--root", "/r", "--fail-on-reports", "--collect", path)
        self.assertEqual(status, 0)

    def test_unparsed_lines_in_other_files_do_not_fail(self):
        # Only report files (ubsan.*) count; a console log has other text.
        path = self.write("test.log", "Building...\n")
        status, out, _ = run("--root", "/r", "--fail-on-reports", "--mixed", path)
        self.assertEqual(status, 0, out)

    def test_unparsed_lines_count_only_in_report_files(self):
        # Not --mixed: a file not named as a report, given as a PATH, has
        # unparsed lines that are counted as such but fail nothing, and a
        # report-named console log with a stray SUMMARY line (unparsed
        # even in a console log) fails nothing either.
        notes = self.write("notes.txt", "garbage\n")
        console = self.write("ubsan.55", "SUMMARY: UndefinedBehaviorSanitizer: invalid-null-argument /r/x.m:1:1\n")
        status, out, _ = run("--root", "/r", "--fail-on-reports", notes, "--console", console)
        self.assertEqual(status, 0, out)
        self.assertIn("Unparsed lines: 2", out)
        self.assertIn("Verdict: PASS", out)

    def test_swift_test_file_name_with_a_module(self):
        self.write("ubsan.ModernTests.SwiftTests.testIt.42", self.report("/r/sources/A.m:1:2", ["-[A b] A.m:1"]))
        status, out, _ = run("--json", "--root", "/r", "--fail-on-reports", self.dir.name)
        (g,) = json.loads(out)["fail_on_reports"]["groups"]
        self.assertEqual(g["tests"], ["SwiftTests.testIt"])
        self.assertEqual(g["pids"], ["42"])

    def test_test_frames_anywhere_in_the_stack(self):
        self.write("ubsan.9", self.report("/r/sources/A.m:1:2", [
            "-[A b]+0x10 (iTerm2.debug.dylib:arm64+0x10)",
            "ModernTests.SwiftTests.testSwift() SwiftTests.swift:12",
            "-[ModernTests.OtherTests testObjC]+0x8 (ModernTests:arm64+0x8)",
            "-[NSInvocation invoke]+0x1a4 (CoreFoundation:arm64e+0x604fc)"]))
        status, out, _ = run("--json", "--root", "/r", "--fail-on-reports", self.dir.name)
        (g,) = json.loads(out)["fail_on_reports"]["groups"]
        self.assertEqual(g["tests"], ["OtherTests.testObjC", "SwiftTests.testSwift"])
        self.assertEqual(g["kind"], "invalid-null-argument")
        self.assertEqual(g["reports"], 1)


REAL = os.path.join(HERE, "fixtures", "sanitizer_nullability_real")
NSSTRING_NOTE = ("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/"
                 "MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSString.h:344:35")
SWIFT_NOTE = ("/r/tmp/sanitizers/nullability/Build/Intermediates.noindex/iTerm2.build/Development/"
              "iTerm2SharedARC.build/DerivedSources/iTerm2SharedARC-Swift.h:7613:54")
ARG1 = "null pointer passed as argument 1, which is declared to never be null"


class NullabilityBaselineTests(unittest.TestCase):
    """--write-nullability-baseline and --nullability-baseline: the known
    nullability report locations, keyed by check kind, file, function,
    message and the base name of the declaring header (not line), compared
    after the run."""

    HEADER = "kind\tfile\tfunction\tmessage\tdeclared\tnote\n"

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.reports = os.path.join(self.dir.name, "reports")
        os.makedirs(self.reports)
        self.baseline = os.path.join(self.dir.name, "baseline.tsv")

    def report_file(self, name, *reports):
        with open(os.path.join(self.reports, name), "w") as f:
            f.write("".join(reports))

    @staticmethod
    def report(path, line, function, kind="invalid-null-argument", argument=1, test=None, note=None,
               summary=True):
        loc = path if path.startswith("/") else "/r/%s" % path
        loc = "%s:%d:5" % (loc, line)
        text = "%s: runtime error: null pointer passed as argument %d, which is declared to never be null\n" % (
            loc, argument)
        if note:
            text += "%s: note: _Nonnull type annotation specified here\n" % note
        if function:
            text += "    #0 0x000100000000 in %s+0x10 (iTerm2.debug.dylib:arm64+0x10)\n" % function
        if test:
            text += "    #1 0x000100000000 in -[%s]+0x8 (ModernTests:arm64+0x8)\n" % test
        if summary:
            text += "\nSUMMARY: UndefinedBehaviorSanitizer: %s %s \n" % (kind, loc)
        return text

    def write_baseline(self, *extra, root="/r"):
        return run("--root", root, "--write-nullability-baseline", self.baseline, *(list(extra) + [self.reports]))

    def entries(self):
        with open(self.baseline) as f:
            return [l.rstrip("\n").split("\t") for l in f if l.strip() and not l.startswith("#")]

    def check(self, *extra):
        return run("--root", "/r", "--fail-on-reports", "--nullability-baseline", self.baseline,
                   *(list(extra) + [self.reports]))

    def test_write_groups_by_function_not_line(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"),
                         self.report("sources/A.m", 20, "-[A one]"))
        self.report_file("ubsan.2", self.report("sources/B.m", 5, "-[B two]", kind="invalid-null-return"),
                         self.report("sources/A.m", 10, "-[A one]"))
        status, out, _ = self.write_baseline()
        self.assertEqual(status, 0, out)
        self.assertIn("Wrote 2 entries to %s: 0 seen and kept, 0 not seen and kept, 2 added, 0 removed."
                      % self.baseline, out)
        self.assertIn("  added: invalid-null-argument  sources/A.m  -[A one]  -", out)
        self.assertEqual(self.entries(), [
            ["kind", "file", "function", "message", "declared", "note"],
            ["invalid-null-argument", "sources/A.m", "-[A one]", ARG1, "-", "untriaged"],
            ["invalid-null-return", "sources/B.m", "-[B two]", ARG1, "-", "untriaged"],
        ])
        with open(self.baseline) as f:
            self.assertTrue(f.read().startswith("#"))

    def test_the_declaring_header_separates_callees(self):
        # The same function, kind and argument: a nil passed to an NSString
        # method and one passed to a ported Swift method are two entries,
        # and the second, new, fails.
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]", note=NSSTRING_NOTE))
        self.write_baseline()
        self.assertEqual(self.entries()[1][4], "NSString.h")
        self.report_file("ubsan.1", self.report("sources/A.m", 12, "-[A one]", note=NSSTRING_NOTE),
                         self.report("sources/A.m", 30, "-[A one]", note=SWIFT_NOTE))
        status, out, _ = self.check()
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 1 report(s) at 1 location(s) outside the baseline; "
                      "1 report(s) accepted by it.", out)
        self.assertIn("declared in iTerm2SharedARC-Swift.h, a generated Swift header: port-relevant", out)
        self.assertIn("Of these, 1 location(s) declared in a generated Swift header (port-relevant).", out)

    def test_real_reports(self):
        # Real report files (2026-11-23, paths moved to /Users/example/iterm2,
        # stacks cut to four frames). ubsan.44108 was cut off after its note
        # line when the host was killed.
        status, out, _ = run("--root", ROOT, "--write-nullability-baseline", self.baseline, REAL)
        self.assertEqual(status, 0, out)
        self.assertIn("warning: skipped 1 incomplete report(s)", out)
        self.assertIn("sanitizer_nullability_real/ubsan.44108", out)
        self.assertEqual([r[:5] for r in self.entries()[1:]], [
            ["invalid-null-argument", "sources/ExternalSessionState/iTermColorMap.m", "-[iTermColorMap savedColorsSlot]",
             ARG1, "iTerm2SharedARC-Swift.h"],
            ["invalid-null-return", "sources/PTYSession/PTYSession.m", "-[PTYSession screenSelection]",
             "null pointer returned from function declared to never return null", "-"],
            ["invalid-null-argument", "sources/PTYSession/PTYSession.m", "-[PTYSession setFilter:]", ARG1,
             "NSString.h"],
        ])
        status, out, _ = run("--root", ROOT, "--fail-on-reports", "--nullability-baseline", self.baseline, REAL)
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 0 report(s) at 0 location(s) outside the baseline; 3 report(s) accepted by it; "
                      "1 incomplete report(s).", out)
        self.assertIn("incomplete report: %s" % os.path.join(REAL, "ubsan.44108"), out)
        self.assertNotIn("candidate for removal", out)

    def test_a_shifted_line_still_matches(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"))
        self.write_baseline()
        self.report_file("ubsan.1", self.report("sources/A.m", 14, "-[A one]"))
        status, out, _ = self.check()
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict: PASS: no report outside the baseline; 1 report(s) accepted by it.", out)

    def test_a_report_outside_the_baseline_fails_with_its_tests(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"))
        self.write_baseline()
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"),
                         self.report("sources/A.m", 30, "-[A one]", argument=2, test="FooTests testBar"),
                         self.report("sources/C.m", 3, "-[C three]"))
        status, out, _ = self.check()
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 2 report(s) at 2 location(s) outside the baseline; "
                      "1 report(s) accepted by it.", out)
        self.assertIn("tests:    FooTests.testBar", out)
        self.assertIn("sources/C.m:3:5", out)
        status, out, _ = self.check("--collect")
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict (--collect, does not fail the run): FAIL", out)

    def test_entries_not_seen_are_candidates_for_removal(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"))
        self.write_baseline()
        os.remove(os.path.join(self.reports, "ubsan.1"))
        status, out, _ = self.check()
        self.assertEqual(status, 0, out)
        self.assertIn("Baseline entries not seen in this run: 1", out)
        self.assertIn("invalid-null-argument  sources/A.m  -[A one]", out)
        self.assertIn("candidate for removal", out)
        self.assertNotIn("remove the entry", out)

    def test_an_incomplete_report_fails_and_is_never_written(self):
        self.report_file("ubsan.7", self.report("sources/A.m", 10, None, summary=False, note=NSSTRING_NOTE))
        status, out, _ = self.write_baseline()
        self.assertEqual(status, 0, out)
        self.assertEqual(self.entries()[1:], [])
        self.assertIn("warning: skipped 1 incomplete report(s)", out)
        status, out, _ = self.check()
        self.assertEqual(status, 1, out)
        self.assertIn("1 incomplete report(s)", out)
        self.assertIn("incomplete report: %s" % os.path.join(self.reports, "ubsan.7"), out)
        self.assertNotIn("sources/A.m:10:5", out.split("Verdict")[1])

    def test_unparsable_report_file_still_fails(self):
        self.write_baseline()
        self.report_file("ubsan.9", "garbage\n")
        status, out, _ = self.check()
        self.assertEqual(status, 1, out)
        self.assertIn("1 report file(s) with lines that are not a report", out)

    def test_unnamed_frame_keys_on_the_line(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, None))
        self.write_baseline()
        self.assertEqual(self.entries()[1][2], "@line 10")

    def test_blocks_lose_their_index_and_sdk_paths_their_version(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "__20-[A one]_block_invoke_3"),
                         self.report("sources/B.m", 10, "__22-[B two:]_block_invoke.448"))
        self.report_file("ubsan.2", self.report(
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/"
            "usr/include/dispatch/once.h", 1, "dispatch_once"),
            self.report("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/"
                        "MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSArray.h", 2,
                        "NSArrayThing"))
        status, out, _ = self.write_baseline()
        self.assertEqual(status, 0, out)
        rows = self.entries()[1:]
        self.assertEqual([(r[1], r[2]) for r in rows], [
            ("System/Library/Frameworks/Foundation.framework/Headers/NSArray.h", "NSArrayThing"),
            ("sources/A.m", "block in -[A one]"),
            ("sources/B.m", "block in -[B two:]"),
            ("usr/include/dispatch/once.h", "dispatch_once"),
        ])

    def test_root_comes_from_the_run_directory(self):
        # Reports under <checkout>/tmp/sanitizers/runs/<run>/reports name
        # their checkout: written relative to it whatever the script's own
        # checkout, and a --root that disagrees is refused.
        checkout = os.path.join(self.dir.name, "lane-12")
        reports = os.path.join(checkout, "tmp", "sanitizers", "runs", "nullability-1", "reports")
        os.makedirs(reports)
        with open(os.path.join(reports, "ubsan.1"), "w") as f:
            f.write(self.report(os.path.join(checkout, "sources", "A.m"), 10, "-[A one]"))
        status, out, _ = run("--write-nullability-baseline", self.baseline, reports)
        self.assertEqual(status, 0, out)
        self.assertEqual(self.entries()[1][1], "sources/A.m")
        status, _, err = run("--root", "/somewhere/else", "--write-nullability-baseline", self.baseline, reports)
        self.assertEqual(status, 2)
        self.assertIn("ran in the checkout %s" % checkout, err)
        self.assertIn("run with the same checkout's script, or pass --root", err)

    def test_an_absolute_path_under_home_is_never_written(self):
        home = os.path.join(self.dir.name, "home")
        other = os.path.join(home, "git", "other-lane", "sources", "A.m")
        self.report_file("ubsan.1", self.report(other, 10, "-[A one]"))
        saved = os.environ.get("HOME")
        os.environ["HOME"] = home
        try:
            status, _, err = self.write_baseline()
        finally:
            if saved is None:
                del os.environ["HOME"]
            else:
                os.environ["HOME"] = saved
        self.assertEqual(status, 2)
        self.assertIn(other, err)
        self.assertIn("run with the same checkout's script, or pass --root", err)
        self.assertFalse(os.path.exists(self.baseline))

    def test_refresh_keeps_notes_and_unseen_entries_and_lists_changes(self):
        self.report_file("ubsan.1", self.report("sources/A.m", 10, "-[A one]"),
                         self.report("sources/B.m", 10, "-[B two]"))
        self.write_baseline()
        with open(self.baseline) as f:
            text = f.read()
        with open(self.baseline, "w") as f:
            f.write(text.replace("-[A one]\t%s\t-\tuntriaged" % ARG1,
                                 "-[A one]\t%s\t-\tnullability-triage.md section 3" % ARG1))
        self.report_file("ubsan.1", self.report("sources/A.m", 12, "-[A one]"),
                         self.report("sources/C.m", 10, "-[C three]"))
        status, out, _ = self.write_baseline()
        self.assertEqual(status, 0, out)
        self.assertIn("Wrote 3 entries to %s: 1 seen and kept, 1 not seen and kept, 1 added, 0 removed."
                      % self.baseline, out)
        self.assertIn("  added: invalid-null-argument  sources/C.m  -[C three]  -", out)
        self.assertIn("  not seen, kept: invalid-null-argument  sources/B.m  -[B two]  -", out)
        notes = {r[2]: r[5] for r in self.entries()[1:]}
        self.assertEqual(notes, {"-[A one]": "nullability-triage.md section 3", "-[B two]": "untriaged",
                                 "-[C three]": "untriaged"})
        status, out, _ = self.write_baseline("--drop-unseen")
        self.assertEqual(status, 0, out)
        self.assertIn("Wrote 2 entries to %s: 2 seen and kept, 0 not seen and kept, 0 added, 1 removed."
                      % self.baseline, out)
        self.assertIn("  removed: invalid-null-argument  sources/B.m  -[B two]  -", out)

    def test_drop_unseen_needs_the_writer(self):
        with self.assertRaises(SystemExit) as cm:
            run("--root", "/r", "--drop-unseen", self.reports)
        self.assertEqual(cm.exception.code, 2)

    def test_malformed_baselines_are_errors(self):
        for text in ("kind\tfile\n", self.HEADER + "a\tb\tc\n",
                     self.HEADER + "k\tf\tfn\tm\td\tn\nk\tf\tfn\tm\td\tother\n"):
            with open(self.baseline, "w") as f:
                f.write(text)
            status, _, err = self.check()
            self.assertEqual(status, 2, text)
            self.assertIn("baseline", err)

    def test_baseline_needs_fail_on_reports(self):
        with open(self.baseline, "w") as f:
            f.write(self.HEADER)
        with self.assertRaises(SystemExit) as cm:
            run("--root", "/r", "--nullability-baseline", self.baseline, self.reports)
        self.assertEqual(cm.exception.code, 2)

    def test_checked_in_baseline_parses(self):
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))),
                            "docs", "swift-migration", "nullability-baseline.tsv")
        entries = sanitizer_summary.read_nullability_baseline(path)
        self.assertIsInstance(entries, list)


if __name__ == "__main__":
    unittest.main()
