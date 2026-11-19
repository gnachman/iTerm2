"""Tests for tools/swift_migration/test_tiers.py (docs/swift-migration/test-tiers.md).

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

The logs are small parallel-format xcodebuild logs written in a temporary
directory, in the form of the real full-suite logs of 2026-11-20 (a
"Command line invocation:" line, "Testing started", per-host suite and
result lines, the "** TEST SUCCEEDED **" marker). Every expected value was
worked out by hand from the log text below.
"""

import io
import json
import os
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS))
sys.path.insert(0, TOOLS)
import test_tiers  # noqa: E402

ASAN = "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project iTerm2.xcodeproj -scheme ModernTests -parallel-testing-enabled YES"
PLAIN = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project iTerm2.xcodeproj "
         "-configuration Development -enableAddressSanitizer NO -enableUndefinedBehaviorSanitizer NO "
         "-scheme ModernTests -enableCodeCoverage NO -enableThreadSanitizer NO ENABLE_THREAD_SANITIZER=NO "
         "\"OTHER_CFLAGS=$(inherited) -fsanitize-ignorelist=/x/sanitizer_ignorelist.txt\" -parallel-testing-enabled YES")
THREAD = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project iTerm2.xcodeproj "
          "-enableAddressSanitizer NO -enableThreadSanitizer YES ENABLE_THREAD_SANITIZER=YES -parallel-testing-enabled NO")
UBSAN = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project iTerm2.xcodeproj "
         "-enableAddressSanitizer NO -enableThreadSanitizer NO "
         "\"OTHER_CFLAGS=$(inherited) -fsanitize-ignorelist=/x -fsanitize=nullability -fsanitize-recover=nullability\"")
FAST = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building -xctestrun "
        "/Users/x/lane/tmp/sanitizers/plain/Build/ModernTests_FastTier.xctestrun -destination platform=macOS "
        "-parallel-testing-enabled YES -skip-testing:ModernTests/FramerFlowTwoHopSimulationTests")
FAST_FULL = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building -xctestrun "
             "/Users/x/lane/tmp/sanitizers/plain/Build/ModernTests_FastTier.xctestrun -destination platform=macOS "
             "-parallel-testing-enabled YES")
COVERAGE = ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project iTerm2.xcodeproj "
            "-enableAddressSanitizer NO \"OTHER_CFLAGS=$(inherited) -fprofile-instr-generate -fcoverage-mapping\"")


def log_text(invocation, results):
    """results: (host, class, method, status, seconds), in log order. A
    suite start line is written whenever a host starts a new class."""
    lines = []
    if invocation is not None:
        lines += ["Command line invocation:", "    " + invocation, ""]
    lines.append("Testing started")
    current = {}
    for host, cls, method, status, seconds in results:
        dest = "My Mac - iTerm2 (%d)" % host
        if current.get(host) != cls:
            lines.append("Test suite '%s' started on '%s'" % (cls, dest))
            current[host] = cls
        lines.append("Test case '%s.%s()' %s on '%s' (%s seconds)" % (cls, method, status, dest, seconds))
    lines += ["", "** TEST SUCCEEDED ** [100.000 sec]", ""]
    return "\n".join(lines)


def run(*args):
    out = io.StringIO()
    err = io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        status = test_tiers.main(list(args))
    return status, out.getvalue(), err.getvalue()


def run_json(*args, expect=0):
    status, out, err = run(*args, "--json")
    assert status == expect, (status, err, out)
    return json.loads(out)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.n = 0

    def write(self, text, name=None):
        self.n += 1
        path = os.path.join(self.tmp.name, name or "log%d.log" % self.n)
        with open(path, "w") as f:
            f.write(text)
        return path


# Three ASan runs. Hosts 1 and 2 interleave.
RUN1 = [(1, "SlowTests", "testA", "passed", "12.000"),
        (2, "MidTests", "testM", "passed", "2.000"),
        (1, "SlowTests", "testB", "passed", "6.000"),
        (2, "MidTests", "testN", "passed", "0.400"),
        (1, "FastTests", "testF", "passed", "0.010"),
        (2, "SkipTests", "testS", "skipped", "0.001")]
RUN2 = [(1, "SlowTests", "testA", "passed", "8.000"),
        (1, "SlowTests", "testB", "failed", "4.000"),
        (2, "MidTests", "testM", "passed", "1.000"),
        (2, "MidTests", "testN", "passed", "0.600"),
        (2, "FastTests", "testF", "passed", "0.020"),
        (2, "SkipTests", "testS", "skipped", "0.001")]
RUN3 = [(3, "SlowTests", "testA", "passed", "10.000"),
        (4, "MidTests", "testM", "passed", "3.000"),
        (3, "SlowTests", "testB", "passed", "5.000"),
        (4, "FastTests", "testF", "passed", "0.030")]


class ModeTests(Base):
    def test_modes_from_invocation(self):
        cases = [(ASAN, "asan"), (PLAIN, "plain"), (THREAD, "thread"), (UBSAN, "ubsan"),
                 (COVERAGE, "coverage"), (FAST, "fast"), (FAST_FULL, "fast-full"),
                 (None, "unknown")]
        for invocation, mode in cases:
            path = self.write(log_text(invocation, RUN3))
            self.assertEqual(test_tiers.log_mode(path), mode, invocation)


class StatsTests(Base):
    def test_max_median_runs(self):
        logs = [self.write(log_text(ASAN, r)) for r in (RUN1, RUN2, RUN3)]
        r = run_json("stats", *logs)
        self.assertEqual(r["mode"], "asan")
        self.assertEqual([l["results"] for l in r["logs"]], [6, 6, 4])
        rows = {t["test"]: t for t in r["tests"]}
        self.assertEqual(rows["SlowTests/testA"]["max"], 12.0)
        self.assertEqual(rows["SlowTests/testA"]["median"], 10.0)
        self.assertEqual(rows["SlowTests/testA"]["runs"], 3)
        # A failed result counts: 6, 4, 5.
        self.assertEqual((rows["SlowTests/testB"]["max"], rows["SlowTests/testB"]["median"]), (6.0, 5.0))
        # Two runs: the median is the mean of the two.
        self.assertEqual((rows["MidTests/testN"]["median"], rows["MidTests/testN"]["runs"]), (0.5, 2))
        # Skipped results are not timings.
        self.assertNotIn("SkipTests/testS", rows)
        self.assertEqual(r["skipped_only"], ["SkipTests/testS"])
        self.assertEqual([t["test"] for t in r["over"]["5"]], ["SlowTests/testA", "SlowTests/testB"])
        self.assertEqual([t["test"] for t in r["over"]["1"]],
                         ["SlowTests/testA", "SlowTests/testB", "MidTests/testM"])
        # By median: testA 10, testB 5, testM 2 (1, 2, 3).
        self.assertEqual([t["test"] for t in r["over_median"]["5"]], ["SlowTests/testA", "SlowTests/testB"])
        self.assertEqual([t["test"] for t in r["over_median"]["10"]], ["SlowTests/testA"])
        self.assertEqual([t["test"] for t in r["over_median"]["1"]],
                         ["SlowTests/testA", "SlowTests/testB", "MidTests/testM"])
        classes = {c["class"]: c for c in r["classes"]}
        self.assertEqual(classes["SlowTests"]["median_total"], 15.0)
        self.assertEqual(classes["SlowTests"]["max_total"], 18.0)
        self.assertEqual(classes["MidTests"]["median_total"], 2.5)
        self.assertEqual(classes["MidTests"]["tests"], 2)
        self.assertEqual(r["classes"][0]["class"], "SlowTests")

    def test_serial_total_per_log(self):
        logs = [self.write(log_text(ASAN, r)) for r in (RUN1, RUN2)]
        r = run_json("stats", *logs)
        self.assertEqual([l["seconds"] for l in r["logs"]], [20.411, 13.621])

    def test_other_modes_and_duplicates_are_left_out(self):
        a = self.write(log_text(ASAN, RUN1))
        same = self.write(log_text(ASAN, RUN1))
        plain = self.write(log_text(PLAIN, RUN2))
        r = run_json("stats", a, same, plain)
        self.assertEqual([l["path"] for l in r["logs"]], [a])
        self.assertEqual(r["left_out"], [{"path": same, "reason": "same content as " + a},
                                         {"path": plain, "reason": "mode plain, not asan"}])
        r = run_json("stats", "--mode", "plain", a, plain)
        self.assertEqual([l["path"] for l in r["logs"]], [plain])

    def test_fast_logs_stay_out_of_the_default(self):
        a = self.write(log_text(ASAN, RUN1))
        fast = self.write(log_text(FAST, RUN3))
        r = run_json("stats", a, fast)
        self.assertEqual([l["path"] for l in r["logs"]], [a])
        self.assertEqual(r["left_out"], [{"path": fast, "reason": "mode fast, not asan"}])

    def test_several_modes(self):
        fast = self.write(log_text(FAST, RUN1))
        plain = self.write(log_text(PLAIN, RUN2))
        a = self.write(log_text(ASAN, RUN3))
        r = run_json("stats", "--mode", "fast,plain", fast, plain, a)
        self.assertEqual(r["mode"], "fast,plain")
        self.assertEqual([l["path"] for l in r["logs"]], [fast, plain])

    def test_no_log_of_the_mode_is_an_error(self):
        plain = self.write(log_text(PLAIN, RUN2))
        status, _, err = run("stats", plain)
        self.assertEqual(status, 2)
        self.assertIn("no log of mode asan", err)

    def test_incomplete_log_is_used_and_flagged(self):
        text = log_text(ASAN, RUN1).replace("** TEST SUCCEEDED ** [100.000 sec]", "")
        r = run_json("stats", self.write(text))
        self.assertFalse(r["logs"][0]["complete"])
        self.assertEqual(len(r["tests"]), 5)

    def test_text_output(self):
        logs = [self.write(log_text(ASAN, r)) for r in (RUN1, RUN2, RUN3)]
        status, out, _ = run("stats", *logs)
        self.assertEqual(status, 0)
        self.assertIn("Tests at or over 5 seconds (by maximum): 2", out)
        self.assertIn("  12.000   10.000  3  SlowTests/testA", out)
        self.assertIn("Tests at or over 1 seconds (by maximum): 3", out)
        self.assertIn("Tests at or over 10 seconds (by median): 1", out)


class SlowListTests(Base):
    def test_parse_and_skip_args(self):
        path = self.write("# comment\n\nSlowTests  over the ceiling: 12 s\n"
                          "MidTests/testM  needs the address sanitizer (bugs.md)\n", "slow.txt")
        status, out, _ = run("skip-args", path)
        self.assertEqual(status, 0)
        self.assertEqual(out, "-skip-testing:ModernTests/SlowTests\n-skip-testing:ModernTests/MidTests/testM\n")

    def test_bad_lists(self):
        bad = ["SlowTests\n",
               "Slow-Tests  reason\n",
               "SlowTests  a\nSlowTests  b\n",
               "SlowTests  a\nSlowTests/testA  b\n",
               "SlowTests/testA/x  a\n"]
        for text in bad:
            status, _, err = run("skip-args", self.write(text, "bad.txt"))
            self.assertEqual(status, 2, text)
            self.assertIn("bad.txt", err)


class BudgetTests(Base):
    def test_fast_and_slow_totals(self):
        slow = self.write("SlowTests  over the ceiling\n", "slow.txt")
        logs = [self.write(log_text(ASAN, r)) for r in (RUN1, RUN2, RUN3)]
        r = run_json("budget", "--slow-tier", slow, *logs)
        self.assertEqual([(l["fast_seconds"], l["slow_seconds"]) for l in r["logs"]],
                         [(2.411, 18.0), (1.621, 12.0), (3.03, 15.0)])
        self.assertEqual(r["fast_median"], 2.411)
        self.assertEqual(r["fast_tests"], 3)
        self.assertEqual(r["slow_tests"], 2)
        # The fast tier's tests at or over 1 second by maximum.
        self.assertEqual([t["test"] for t in r["fast_over_1"]], ["MidTests/testM"])
        self.assertEqual(r["stale"], [])

    def test_fast_over_1_is_by_median(self):
        # testN: 0.4 and 0.6 (median 0.5) stays; a test over 1 second only
        # in its worst run is not listed.
        runs = [RUN1, RUN2, [(1, "MidTests", "testN", "passed", "3.000")] + RUN3]
        slow = self.write("SlowTests  over the ceiling\n", "slow.txt")
        r = run_json("budget", "--slow-tier", slow, *[self.write(log_text(ASAN, x)) for x in runs])
        self.assertEqual([t["test"] for t in r["fast_over_1"]], ["MidTests/testM"])

    def test_propose(self):
        slow = self.write("MidTests/testM  already listed\n", "slow.txt")
        logs = [self.write(log_text(ASAN, r)) for r in (RUN1, RUN2, RUN3)]
        status, out, _ = run("propose", "--slow-tier", slow, *logs)
        self.assertEqual(status, 0)
        self.assertEqual(out,
                         "SlowTests/testA  ceiling: median 10.000 s, max 12.000 s in 3 asan runs\n"
                         "SlowTests/testB  one second: median 5.000 s, max 6.000 s in 3 asan runs\n")

    def test_stale_entries_are_reported(self):
        slow = self.write("SlowTests  x\nGoneTests  y\nMidTests/testGone  z\n", "slow.txt")
        r = run_json("budget", "--slow-tier", slow, self.write(log_text(ASAN, RUN1)))
        self.assertEqual(r["stale"], ["GoneTests", "MidTests/testGone"])


class StripEnvTests(Base):
    """strip-env: the .xctestrun fast_tests.sh runs, without MallocStackLogging."""

    def plist(self, data):
        import plistlib
        path = os.path.join(self.tmp.name, "in.xctestrun")
        with open(path, "wb") as f:
            plistlib.dump(data, f)
        return path

    def read(self, path):
        import plistlib
        with open(path, "rb") as f:
            return plistlib.load(f)

    ENV = {"ASAN_OPTIONS": "malloc_context_size=0", "MallocStackLogging": "YES",
           "MallocStackLoggingDirectory": "/tmp", "MallocStackLoggingNoCompact": "1",
           "MallocScribble": "1", "NSZombieEnabled": "YES"}

    def test_format_2(self):
        src = self.plist({"TestConfigurations": [{"Name": "Test Scheme Action", "TestTargets": [
            {"BlueprintName": "ModernTests", "EnvironmentVariables": dict(self.ENV),
             "TestingEnvironmentVariables": {"DYLD_LIBRARY_PATH": "x", "MallocStackLogging": "YES"}}]}],
            "ContainerInfo": {"ContainerName": "iTerm2", "SchemeName": "ModernTests"},
            "__xctestrun_metadata__": {"FormatVersion": 2}})
        out = os.path.join(self.tmp.name, "out.xctestrun")
        status, text, _ = run("strip-env", src, out)
        self.assertEqual(status, 0)
        target = self.read(out)["TestConfigurations"][0]["TestTargets"][0]
        self.assertEqual(target["EnvironmentVariables"], {"ASAN_OPTIONS": "malloc_context_size=0",
                                                          "MallocScribble": "1", "NSZombieEnabled": "YES"})
        self.assertEqual(target["TestingEnvironmentVariables"], {"DYLD_LIBRARY_PATH": "x"})
        self.assertEqual(self.read(out)["__xctestrun_metadata__"], {"FormatVersion": 2})
        self.assertIn("Removed 4 variable(s) from 1 test target(s): MallocStackLogging, "
                      "MallocStackLoggingDirectory, MallocStackLoggingNoCompact", text)

    def test_format_1(self):
        src = self.plist({"ModernTests": {"EnvironmentVariables": dict(self.ENV)},
                          "__xctestrun_metadata__": {"FormatVersion": 1}})
        out = os.path.join(self.tmp.name, "out.xctestrun")
        status, _, _ = run("strip-env", src, out)
        self.assertEqual(status, 0)
        self.assertNotIn("MallocStackLogging", self.read(out)["ModernTests"]["EnvironmentVariables"])

    def test_no_target_is_an_error(self):
        src = self.plist({"__xctestrun_metadata__": {"FormatVersion": 2}, "TestConfigurations": []})
        status, _, err = run("strip-env", src, os.path.join(self.tmp.name, "out.xctestrun"))
        self.assertEqual(status, 2)
        self.assertIn("no test target", err)

    def test_nothing_removed_is_an_error(self):
        # The fast tier must not run with MallocStackLogging unnoticed: if
        # the test plan changes so that there is nothing to remove, say so.
        env = {k: v for k, v in self.ENV.items() if not k.startswith("MallocStackLogging")}
        src = self.plist({"TestConfigurations": [{"TestTargets": [{"EnvironmentVariables": env}]}]})
        status, _, err = run("strip-env", src, os.path.join(self.tmp.name, "out.xctestrun"))
        self.assertEqual(status, 2)
        self.assertIn("no MallocStackLogging variable", err)


# Fast-tier runs for the removal proposals. In RUN1 to RUN3, MidTests/testM
# takes 2, 1, 3 s (median 2); SlowTests/testA 12, 8, 10.
FAST1 = [(1, "SlowTests", "testA", "passed", "0.500"), (1, "MidTests", "testM", "passed", "0.900"),
         (2, "MidTests", "testN", "passed", "0.100")]
FAST2 = [(1, "SlowTests", "testA", "passed", "0.700"), (1, "MidTests", "testM", "passed", "1.500")]
FAST3 = [(1, "SlowTests", "testA", "passed", "0.600"), (1, "MidTests", "testM", "passed", "1.200")]


class ProposeRemovalsTests(Base):
    """propose-removals: entries put in the slow tier for their time
    ("one second" or "ceiling") whose median is under one second over at
    least --min-runs runs (default 3) in logs of the whole suite run as the
    fast tier runs (fast_tests.sh --no-skip: mode fast-full, the default),
    or plain runs. A fast-tier run skips these tests, so it is no evidence."""

    LIST = ("FramerFlowTwoHopSimulationTests  owner decision (owner-queue.md Q22)\n"
            "SlowTests/testA  ceiling: median 10.000 s, max 12.000 s in 3 asan runs\n"
            "MidTests/testM  one second: median 2.000 s, max 3.000 s in 3 asan runs\n"
            "GoneTests/testG  one second: median 1.500 s, max 2.000 s in 3 asan runs\n")

    def test_removals(self):
        slow = self.write(self.LIST, "slow.txt")
        logs = [self.write(log_text(FAST_FULL, r)) for r in (FAST1, FAST2, FAST3)]
        status, out, err = run("propose-removals", "--slow-tier", slow, *logs)
        self.assertEqual(status, 0, err)
        # testA: 0.5, 0.7, 0.6, median 0.6 over 3 runs: proposed. testM:
        # median 1.2: stays. The owner's class is not judged by time.
        self.assertIn("SlowTests/testA  median 0.600 s, max 0.700 s in 3 fast-full runs (listed: ceiling", out)
        self.assertNotIn("MidTests/testM  median", out)
        self.assertNotIn("FramerFlowTwoHop", out.split("By class")[0].split("Not enough runs")[0])

    def test_min_runs(self):
        slow = self.write(self.LIST, "slow.txt")
        logs = [self.write(log_text(FAST_FULL, r)) for r in (FAST1, FAST2)]
        r = run_json("propose-removals", "--slow-tier", slow, *logs)
        self.assertEqual(r["remove"], [])
        self.assertEqual(sorted(t["test"] for t in r["too_few_runs"]), ["MidTests/testM", "SlowTests/testA"])
        r = run_json("propose-removals", "--slow-tier", slow, "--min-runs", "2", *logs)
        self.assertEqual([t["test"] for t in r["remove"]], ["SlowTests/testA"])
        self.assertEqual(r["remove"][0]["median"], 0.6)

    def test_by_class_table(self):
        slow = self.write(self.LIST, "slow.txt")
        logs = [self.write(log_text(FAST_FULL, r)) for r in (FAST1, FAST2, FAST3)]
        r = run_json("propose-removals", "--slow-tier", slow, *logs)
        self.assertEqual(r["by_class"], [{"class": "SlowTests", "remove": 1, "listed": 1}])
        status, out, _ = run("propose-removals", "--slow-tier", slow, *logs)
        self.assertIn("By class (entries proposed for removal of those listed for their time):", out)
        self.assertIn("     1 of      1  SlowTests", out)

    def test_plain_logs_count_too(self):
        slow = self.write(self.LIST, "slow.txt")
        logs = [self.write(log_text(PLAIN, r)) for r in (FAST1, FAST2, FAST3)]
        r = run_json("propose-removals", "--slow-tier", slow, "--mode", "fast-full,plain", *logs)
        self.assertEqual([t["test"] for t in r["remove"]], ["SlowTests/testA"])


class CheckedInListTests(unittest.TestCase):
    """The list fast_tests.sh uses."""

    PATH = os.path.join(TOOLS, "slow_tier.txt")

    def test_it_parses(self):
        entries = test_tiers.read_slow_tier(self.PATH)
        self.assertTrue(entries)
        for e in entries:
            self.assertTrue(e["reason"])

    def test_every_class_exists_in_modern_tests(self):
        names = set()
        decl = re.compile(r"^\s*(?:(?:final|public|private|fileprivate|internal|open|@objc\S*)\s+)*class\s+(\w+)\s*:|"
                          r"^@interface\s+(\w+)\s*:|^@implementation\s+(\w+)")
        for dirpath, _, filenames in os.walk(os.path.join(REPO, "ModernTests")):
            for name in filenames:
                if name.endswith((".swift", ".m", ".mm")):
                    with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as f:
                        for line in f:
                            m = decl.match(line)
                            if m:
                                names.add(next(g for g in m.groups() if g))
        for e in test_tiers.read_slow_tier(self.PATH):
            self.assertIn(e["class"], names, e["id"])

    def test_every_method_exists_in_modern_tests(self):
        methods = set()
        decl = re.compile(r"\bfunc\s+(test\w*)\s*\(|^-\s*\(void\)\s*(test\w*)\b")
        for dirpath, _, filenames in os.walk(os.path.join(REPO, "ModernTests")):
            for name in filenames:
                if name.endswith((".swift", ".m", ".mm")):
                    with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as f:
                        for line in f:
                            for m in decl.finditer(line):
                                methods.add(m.group(1) or m.group(2))
        missing = [e["id"] for e in test_tiers.read_slow_tier(self.PATH)
                   if e["method"] is not None and e["method"] not in methods]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
