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


if __name__ == "__main__":
    unittest.main()
