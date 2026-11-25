"""Tests for tools/swift_migration/fast_tests.sh, with xcodebuild, otool, ps
and pkill replaced by stubs.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

Each test copies the script and what it uses into a temporary root and puts
a directory of stubs first on PATH:

- xcodebuild: for build-for-testing, creates the test host's directory and
  an .xctestrun file (with the MallocStackLogging variables the test plan
  sets) under SYMROOT; for test-without-building, writes its arguments to
  $STUB_DIR/test-args, exits 3 if the .xctestrun it was given still sets
  MallocStackLogging, and otherwise prints a short parallel test log and
  exits with $STUB_TEST_STATUS. Every invocation is appended to
  $STUB_DIR/calls.
- otool: lists no sanitizer runtime.
- ps, pkill: print nothing, so no real process is ever matched.

With $STUB_HANG the test step prints a suite's start and then goes silent,
for the stall watchdog. The whole-suite lock is a file in the test's
temporary directory (SWIFT_MIGRATION_SUITE_LOCK), never the machine's real
one; the stub records whether its test step ran under it
($STUB_DIR/test-held).

Nothing is built and nothing is run but the scripts and the stubs.
"""

import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS))

COPIED = ["fast_tests.sh", "sanitizer_tests.sh", "sanitizer_common.sh", "sanitizer_summary.py",
          "test_timing.py", "test_tiers.py", "slow_tier.txt", "sanitizer_ignorelist.txt",
          "sanitizer_nullability_suppressions.txt", "suite_guard.py", "deadline_run.py",
          "test_load_profile.py"]

XCODEBUILD = r"""#!/bin/bash
echo "$*" >> "$STUB_DIR/calls"
action="$1"; shift
symroot=""
xctestrun=""
prev=""
for a in "$@"; do
    case "$a" in SYMROOT=*) symroot="${a#SYMROOT=}";; esac
    [ "$prev" = "-xctestrun" ] && xctestrun="$a"
    prev="$a"
done
if [ "$action" = build-for-testing ]; then
    mkdir -p "$symroot/Development/iTerm2.app/Contents/MacOS"
    : > "$symroot/Development/iTerm2.app/Contents/MacOS/iTerm2.debug.dylib"
    cat > "$symroot/ModernTests_ModernTests_macosx27.0-$(uname -m).xctestrun" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ContainerInfo</key>
	<dict><key>SchemeName</key><string>ModernTests</string></dict>
	<key>TestConfigurations</key>
	<array><dict>
		<key>Name</key><string>Test Scheme Action</string>
		<key>TestTargets</key>
		<array><dict>
			<key>BlueprintName</key><string>ModernTests</string>
			<key>EnvironmentVariables</key>
			<dict>
				<key>MallocScribble</key><string>1</string>
				<key>MallocStackLogging</key><string>YES</string>
				<key>MallocStackLoggingDirectory</key><string>/tmp</string>
				<key>MallocStackLoggingNoCompact</key><string>1</string>
			</dict>
		</dict></array>
	</dict></array>
	<key>__xctestrun_metadata__</key>
	<dict><key>FormatVersion</key><integer>2</integer></dict>
</dict>
</plist>
EOF
    exit 0
fi
if [ "$action" = test-without-building ]; then
    echo "$*" > "$STUB_DIR/test-args"
    printf '%s' "${SWIFT_MIGRATION_SUITE_LOCK_HELD:-}" > "$STUB_DIR/test-held"
    if [ -n "${STUB_HANG:-}" ]; then
        echo "Test suite 'HangTests' started on 'My Mac - iTerm2 (1)'"
        echo $$ > "$STUB_DIR/hang.pid"
        exec sleep 600
    fi
    if grep -q MallocStackLogging "$xctestrun"; then echo "stub: MallocStackLogging still set" >&2; exit 3; fi
    grep -q MallocScribble "$xctestrun" || { echo "stub: other variables lost" >&2; exit 4; }
    echo "Command line invocation:"
    echo "    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building $*"
    [ -t 1 ] && echo "stub: stdout is a terminal"
    if echo "$*" | grep -q -- "-parallel-testing-enabled NO"; then
        echo "Test Suite 'Selected tests' started at 2026-11-20 01:08:28.898."
        echo "Test Suite 'ModernTests.xctest' started at 2026-11-20 01:08:28.898."
        echo "Test Suite 'ProbeTests' started at 2026-11-20 01:08:28.899."
        if [ -z "$STUB_NO_TESTS" ]; then
            echo "Test Case '-[ModernTests.ProbeTests testA]' started."
            echo "Test Case '-[ModernTests.ProbeTests testA]' passed (0.003 seconds)."
            echo "Test Case '-[ModernTests.ProbeTests testX]' started."
            echo "Test Case '-[ModernTests.ProbeTests testX]' recorded an expected failure (0.002 seconds)."
            n=2; t=0.005
        else
            n=0; t=0.000
        fi
        echo "Test Suite 'ProbeTests' passed at 2026-11-20 01:08:28.902."
        echo "	 Executed $n tests, with 0 failures (0 unexpected) in $t ($t) seconds"
        echo "Test Suite 'ModernTests.xctest' passed at 2026-11-20 01:08:28.903."
        echo "	 Executed $n tests, with 0 failures (0 unexpected) in $t ($t) seconds"
        echo "Test Suite 'Selected tests' passed at 2026-11-20 01:08:28.903."
        echo "	 Executed $n tests, with 0 failures (0 unexpected) in $t ($t) seconds"
    else
        echo "Testing started"
        # A suite every test of which -skip-testing removed: started, no result.
        echo "Test suite 'FramerFlowTwoHopSimulationTests' started on 'My Mac - iTerm2 (2)'"
        if [ -z "$STUB_NO_TESTS" ]; then
            echo "Test suite 'ProbeTests' started on 'My Mac - iTerm2 (1)'"
            # One line with a carriage return of its own, which the terminal
            # doubles (seen in the real run of 2026-11-20).
            printf "Test case 'ProbeTests.testA()' passed on 'My Mac - iTerm2 (1)' (0.003 seconds)\r\n"
            echo "Test case 'ProbeTests.testX()' recorded an expected failure on 'My Mac - iTerm2 (1)' (0.002 seconds)"
            echo "Test case 'ProbeTests.testSlow()' passed on 'My Mac - iTerm2 (1)' (12.500 seconds)"
            if [ -n "${STUB_TIMEOUT_FORM:-}" ]; then
                # What test-without-building printed for a test over a 60
                # second allowance (a real run, 2026-11-24): no "exceeded
                # execution time allowance" line, only the failure.
                echo "Test case 'ProbeTests.testHung()' failed on 'My Mac - iTerm2 (1)' (60.000 seconds)"
            fi
        fi
    fi
    # xcodebuild prints its end marker on the other stream.
    echo "** TEST EXECUTE SUCCEEDED ** [1.000 sec]" >&2
    exit "${STUB_TEST_STATUS:-0}"
fi
exit 9
"""
OTOOL = "#!/bin/sh\necho \"$2:\"\necho \"\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\"\n"
NOTHING = "#!/bin/sh\nexit 0\n"


class FastTestsTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        root = os.path.join(self.dir.name, "checkout")
        tools = os.path.join(root, "tools", "swift_migration")
        os.makedirs(tools)
        for name in COPIED:
            shutil.copy2(os.path.join(TOOLS, name), tools)
        for d in ("xcstrings", "sources"):
            os.makedirs(os.path.join(root, d))
            open(os.path.join(root, d, "Localizable.xcstrings"), "w").close()
        stubs = os.path.join(self.dir.name, "stubs")
        os.makedirs(stubs)
        for name, text in (("xcodebuild", XCODEBUILD), ("otool", OTOOL), ("ps", NOTHING), ("pkill", NOTHING)):
            path = os.path.join(stubs, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.root = root
        self.stubs = stubs
        self.entries = []
        with open(os.path.join(TOOLS, "slow_tier.txt")) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    self.entries.append(line.split(None, 1)[0])

    def run_script(self, *args, test_status=0, no_tests=False, stubs=True, env=None):
        extra = env or {}
        env = dict(os.environ)
        env.update(extra)
        if stubs:
            env["PATH"] = self.stubs + os.pathsep + env["PATH"]
        env["STUB_DIR"] = self.stubs
        env["STUB_TEST_STATUS"] = str(test_status)
        self.lock = os.path.join(self.dir.name, "locks", "whole-suite.lock")
        env["SWIFT_MIGRATION_SUITE_LOCK"] = self.lock
        env.pop("SWIFT_MIGRATION_SUITE_LOCK_HELD", None)
        if no_tests:
            env["STUB_NO_TESTS"] = "1"
        p = subprocess.run(["bash", os.path.join(self.root, "tools", "swift_migration", "fast_tests.sh")] + list(args),
                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
        return p.returncode, p.stdout

    def calls(self):
        path = os.path.join(self.stubs, "calls")
        if not os.path.exists(path):
            return []
        with open(path) as f:
            return f.read().splitlines()

    def test_dry_run_prints_commands_and_runs_nothing(self):
        status, out = self.run_script("--dry-run")
        self.assertEqual(status, 0, out)
        self.assertEqual(self.calls(), [])
        self.assertIn("tools/swift_migration/sanitizer_tests.sh plain --build-only", out)
        self.assertIn("test_tiers.py strip-env ", out)
        self.assertIn("ModernTests_FastTier.xctestrun", out)
        test_lines = [l for l in out.splitlines() if l.startswith("xcodebuild test-without-building")]
        self.assertEqual(len(test_lines), 1, out)
        command = test_lines[0]
        self.assertIn("-xctestrun " + os.path.join(self.root, "tmp/sanitizers/plain/Build/ModernTests_FastTier.xctestrun"),
                      command)
        self.assertIn("-parallel-testing-enabled YES", command)
        skips = [a for a in command.split() if a.startswith("-skip-testing:")]
        self.assertEqual(skips, ["-skip-testing:ModernTests/" + e for e in self.entries])
        self.assertIn("-skip-testing:ModernTests/FramerFlowTwoHopSimulationTests/"
                      "testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp", skips)
        self.assertIn("Slow tier: %d entries skipped" % len(self.entries), out)
        self.assertIn("FramerFlowTwoHopSimulationTests/testANestedFloodRecoversWhenAJitteryOuterHopSpeedsUp  owner decision",
                      out)
        self.assertIn("No address sanitizer, no MallocStackLogging", out)

    def test_dry_run_no_skip(self):
        # The whole suite as the fast tier runs it: the evidence
        # test_tiers.py propose-removals needs.
        status, out = self.run_script("--dry-run", "--no-skip")
        self.assertEqual(status, 0, out)
        command = [l for l in out.splitlines() if l.startswith("xcodebuild test-without-building")][0]
        self.assertNotIn("-skip-testing:", command)
        self.assertIn("--no-skip: no test is skipped", out)

    def test_dry_run_serial(self):
        status, out = self.run_script("--dry-run", "--serial")
        self.assertEqual(status, 0, out)
        self.assertIn("-parallel-testing-enabled NO", out)
        self.assertNotIn("-parallel-testing-worker-count", out)
        self.assertNotIn("-maximum-parallel-testing-workers", out)

    def dry_run_test_command(self, *args):
        status, out = self.run_script("--dry-run", *args)
        self.assertEqual(status, 0, out)
        return [l for l in out.splitlines() if l.startswith("xcodebuild test-without-building")][0], out

    def test_parallel_defaults_to_two_workers(self):
        # The cap of tools/run_tests.expect -parallel.
        command, _ = self.dry_run_test_command()
        self.assertIn("-parallel-testing-enabled YES -parallel-testing-worker-count 2 "
                      "-maximum-parallel-testing-workers 2", command)

    def test_workers_changes_the_count(self):
        command, _ = self.dry_run_test_command("--workers", "3")
        self.assertIn("-parallel-testing-worker-count 3 -maximum-parallel-testing-workers 3", command)

    def test_workers_with_serial_is_a_usage_error(self):
        status, out = self.run_script("--serial", "--workers", "2")
        self.assertEqual(status, 2, out)
        self.assertIn("--workers needs a parallel run", out)
        self.assertEqual(self.calls(), [])

    def test_jobs_is_passed_to_the_build(self):
        _, out = self.dry_run_test_command("--jobs", "4")
        self.assertIn("tools/swift_migration/sanitizer_tests.sh plain --build-only --jobs 4", out)
        status, out = self.run_script("--jobs", "4")
        self.assertEqual(status, 0, out)
        calls = self.calls()
        self.assertTrue(calls[0].startswith("build-for-testing "), calls)
        self.assertIn(" -jobs 4", calls[0])
        # The test step builds nothing.
        self.assertNotIn("-jobs", calls[-1])

    def test_jobs_without_a_build_is_a_usage_error(self):
        status, out = self.run_script("--no-build", "--jobs", "2")
        self.assertEqual(status, 2, out)
        self.assertIn("--jobs applies to the build, which --no-build leaves out", out)
        self.assertEqual(self.calls(), [])

    def test_no_jobs_by_default(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        self.assertNotIn("-jobs", self.calls()[0])

    def test_bad_counts_are_usage_errors(self):
        for option in ("--jobs", "--workers"):
            for args in ((option,), (option, "0"), (option, "x")):
                status, out = self.run_script(*args)
                self.assertEqual(status, 2, (args, out))
                self.assertEqual(self.calls(), [], args)

    def run_log_and_timing(self):
        runs = os.path.join(self.root, "tmp", "fast-tests", "runs")
        last = os.path.join(runs, sorted(os.listdir(runs))[-1])
        with open(os.path.join(last, "test.log"), newline="") as f:
            log = f.read()
        with open(os.path.join(last, "timing.txt")) as f:
            timing = f.read()
        return log, timing

    def test_run_is_on_a_terminal_and_its_timing_is_clean(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        log, timing = self.run_log_and_timing()
        # Through a pty: xcodebuild's two streams stay in order.
        self.assertIn("stub: stdout is a terminal", log)
        self.assertTrue(log.startswith("Command line invocation:"), log[:80])
        self.assertNotIn("\r", log)
        self.assertNotIn("WARNING", timing)
        self.assertIn("Test-case results parsed: 3 (passed 3, failed 0, skipped 0)", timing)

    def test_serial_run_that_passed_exits_0(self):
        status, out = self.run_script("--serial")
        self.assertEqual(status, 0, out)
        log, timing = self.run_log_and_timing()
        self.assertNotIn("WARNING", timing)
        self.assertIn("Test-case results parsed: 2 (passed 2, failed 0, skipped 0)", timing)

    def test_serial_run_with_no_tests_fails(self):
        status, out = self.run_script("--serial", no_tests=True)
        self.assertEqual(status, 1, out)
        self.assertIn("executed no tests", out)

    def test_run_builds_strips_and_tests(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        calls = self.calls()
        self.assertTrue(calls[0].startswith("build-for-testing "), calls)
        self.assertIn("-enableAddressSanitizer NO", calls[0])
        self.assertTrue(calls[-1].startswith("test-without-building "), calls)
        with open(os.path.join(self.stubs, "test-args")) as f:
            args = f.read().split()
        self.assertEqual(len([a for a in args if a.startswith("-skip-testing:")]), len(self.entries))
        self.assertIn("Removed 3 variable(s) from 1 test target(s)", out)
        # The ceiling is reported, not enforced.
        self.assertIn("ProbeTests/testSlow", out)
        self.assertIn("at or over the 10-second ceiling", out)

    def test_no_build(self):
        self.run_script()
        open(os.path.join(self.stubs, "calls"), "w").close()
        status, out = self.run_script("--no-build")
        self.assertEqual(status, 0, out)
        self.assertEqual([c.split()[0] for c in self.calls()], ["test-without-building"])

    def test_no_build_without_a_build_fails(self):
        status, out = self.run_script("--no-build")
        self.assertEqual(status, 1, out)
        self.assertIn("no .xctestrun", out)

    def test_test_failure_status_is_kept(self):
        status, out = self.run_script(test_status=65)
        self.assertEqual(status, 65, out)

    def test_no_tests_executed_fails(self):
        status, out = self.run_script(no_tests=True)
        self.assertEqual(status, 1, out)
        self.assertIn("executed no tests", out)

    def test_kill_matches_the_exact_test_host_path_only(self):
        # Real processes: copies of a small sleeping program at the test
        # host's path under this checkout, at the same path under another
        # checkout, at a path that only starts with the host's, and at an
        # unrelated .../iTerm2. (A copy of /bin/sleep cannot be used: the
        # system kills a copied platform binary at launch.)
        sleeper = os.path.join(self.dir.name, "sleeper")
        with open(sleeper + ".c", "w") as f:
            f.write("#include <unistd.h>\nint main(void) { sleep(300); return 0; }\n")
        subprocess.run(["cc", "-o", sleeper, sleeper + ".c"], check=True, timeout=120)
        host = os.path.join(self.root, "tmp/sanitizers/plain/Build/Development/iTerm2.app/Contents/MacOS/iTerm2")
        other_lane = os.path.join(self.dir.name, "other-lane",
                                  "tmp/sanitizers/plain/Build/Development/iTerm2.app/Contents/MacOS/iTerm2")
        longer = host + "Helper"
        unrelated = os.path.join(self.dir.name, "Applications/iTerm2.app/Contents/MacOS/iTerm2")
        procs = {}
        for name, path in (("host", host), ("other_lane", other_lane), ("longer", longer),
                           ("unrelated", unrelated)):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            shutil.copy(sleeper, path)
            procs[name] = subprocess.Popen([path, "300"])
        # The script sees only these processes: real ps output filtered to
        # this test's directory, so that even a wrong matcher can kill
        # nothing but them.
        fake_ps = os.path.join(self.dir.name, "own-ps")
        with open(fake_ps, "w") as f:
            f.write("#!/bin/sh\n/bin/ps \"$@\" | grep -F '%s'\n" % self.dir.name)
        os.chmod(fake_ps, 0o755)
        try:
            # All four are running before the kill step.
            for name, p in procs.items():
                self.assertIsNone(p.poll(), name)
            status, out = self.run_script("--kill-test-hosts", stubs=False, env={"FAST_TESTS_PS": fake_ps})
            self.assertEqual(status, 0, out)
            self.assertEqual(procs["host"].wait(timeout=30), -9)
            for name in ("other_lane", "longer", "unrelated"):
                self.assertIsNone(procs[name].poll(), name)
        finally:
            for p in procs.values():
                if p.poll() is None:
                    p.kill()
                p.wait()

    def set_budget(self, seconds):
        """Changes the budget constant in the copied script (a budget below
        zero makes any run go over without waiting)."""
        path = os.path.join(self.root, "tools", "swift_migration", "fast_tests.sh")
        with open(path) as f:
            text = f.read()
        self.assertEqual(text.count("\nFAST_TIER_BUDGET_SECONDS=300\n"), 1)
        with open(path, "w") as f:
            f.write(text.replace("\nFAST_TIER_BUDGET_SECONDS=300\n", "\nFAST_TIER_BUDGET_SECONDS=%d\n" % seconds))

    def test_whole_command_is_reported_against_the_budget(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        self.assertRegex(out, r"Whole command: \d+ s; fast tier budget 300 s \(FAST_TIER_BUDGET_SECONDS\): under\.")

    def test_over_budget_is_reported_and_fails_only_when_enforced(self):
        self.set_budget(-1)
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        self.assertRegex(out, r"Whole command: \d+ s; fast tier budget -1 s \(FAST_TIER_BUDGET_SECONDS\): OVER\.")
        self.assertIn("not enforced (no --enforce-budget)", out)
        status, out = self.run_script("--enforce-budget")
        self.assertEqual(status, 1, out)
        self.assertIn("error: the fast tier went over its budget", out)

    def test_enforce_budget_is_refused_where_it_would_do_nothing(self):
        for other in ("--dry-run", "--kill-test-hosts"):
            status, out = self.run_script("--enforce-budget", other)
            self.assertEqual(status, 2, (other, out))
            self.assertIn("--enforce-budget applies to a run", out)
            self.assertEqual(self.calls(), [])

    def test_enforced_budget_keeps_a_test_failure_status(self):
        self.set_budget(-1)
        status, out = self.run_script("--enforce-budget", test_status=65)
        self.assertEqual(status, 65, out)

    def test_unknown_option(self):
        status, out = self.run_script("--frobnicate")
        self.assertEqual(status, 2, out)

    # The stall watchdog and the whole-suite lock (2026-11-24).

    def last_run_dir(self):
        runs = os.path.join(self.root, "tmp", "fast-tests", "runs")
        return os.path.join(runs, sorted(os.listdir(runs))[-1])

    def test_a_silent_test_step_is_stopped_and_reported(self):
        status, out = self.run_script("--stall-seconds", "2", env={"STUB_HANG": "1"})
        self.assertEqual(status, 124, out)
        self.assertIn("looks stalled (--stall-seconds 2): no test progress for 2 seconds", out)
        self.assertIn("stalled and was stopped by the watchdog (status 124)", out)
        with open(os.path.join(self.last_run_dir(), "stall", "stall.txt")) as f:
            stall = f.read()
        self.assertIn("STALLED", stall)
        self.assertIn("worker My Mac - iTerm2 (1): class in progress (log): HangTests", stall)
        with open(os.path.join(self.stubs, "hang.pid")) as f:
            pid = int(f.read())
        for _ in range(200):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            self.fail("the silent stand-in xcodebuild %d is still running" % pid)

    def test_the_watchdog_defaults_and_its_option(self):
        _, out = self.dry_run_test_command()
        # The allowance (60) plus 300.
        self.assertIn("--stall-seconds 360", out)
        _, out = self.dry_run_test_command("--test-allowance-seconds", "600")
        self.assertIn("--stall-seconds 900", out)
        _, out = self.dry_run_test_command("--test-allowance-seconds", "0")
        self.assertIn("--stall-seconds 300", out)
        _, out = self.dry_run_test_command("--stall-seconds", "0")
        self.assertIn("--stall-seconds 0", out)
        for value in ("", "x", "-3"):
            status, out = self.run_script("--stall-seconds", value)
            self.assertEqual(status, 2, (value, out))
            self.assertEqual(self.calls(), [], value)

    def test_the_per_test_allowance_and_the_result_bundle(self):
        command, _ = self.dry_run_test_command()
        self.assertIn("-test-timeouts-enabled YES -default-test-execution-time-allowance 60 "
                      "-maximum-test-execution-time-allowance 60", command)
        self.assertRegex(command, r"-resultBundlePath \S*/tmp/fast-tests/runs/[0-9-]+/results/test\.xcresult")
        command, _ = self.dry_run_test_command("--test-allowance-seconds", "120", "--max-test-allowance-seconds",
                                               "300")
        self.assertIn("-default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300",
                      command)
        command, _ = self.dry_run_test_command("--test-allowance-seconds", "0")
        self.assertNotIn("-test-timeouts-enabled", command)
        status, out = self.run_script("--test-allowance-seconds", "300", "--max-test-allowance-seconds", "60")
        self.assertEqual(status, 2, out)
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        with open(os.path.join(self.stubs, "test-args")) as f:
            self.assertIn("-default-test-execution-time-allowance 60", f.read())

    def test_the_test_step_holds_the_whole_suite_lock(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        with open(os.path.join(self.stubs, "test-held")) as f:
            self.assertTrue(f.read().endswith(":" + self.lock))
        self.assertRegex(out, r"(?m)^fast_tests\.sh: pid [0-9]+$")

    def test_the_budget_leaves_out_the_wait_for_the_lock(self):
        import sys
        import re
        if TOOLS not in sys.path:
            sys.path.insert(0, TOOLS)
        import suite_guard
        self.run_script("--dry-run")  # sets self.lock
        lock = suite_guard.SuiteLock(self.lock)
        self.assertTrue(lock.acquire("a sanitized suite in another lane", ["xcodebuild"], wait=False))
        self.addCleanup(lock.release)
        env = dict(os.environ)
        env["PATH"] = self.stubs + os.pathsep + env["PATH"]
        env.update({"STUB_DIR": self.stubs, "STUB_TEST_STATUS": "0", "SWIFT_MIGRATION_SUITE_LOCK": self.lock})
        env.pop("SWIFT_MIGRATION_SUITE_LOCK_HELD", None)
        out_path = os.path.join(self.dir.name, "queued.out")
        began = time.monotonic()
        with open(out_path, "w") as out:
            p = subprocess.Popen(["bash", os.path.join(self.root, "tools", "swift_migration", "fast_tests.sh"),
                                  "--enforce-budget"], env=env, stdout=out, stderr=subprocess.STDOUT)
        self.addCleanup(lambda: p.poll() is None and (p.kill(), p.wait()))

        def text():
            with open(out_path) as f:
                return f.read()
        for _ in range(1200):
            if "waiting for the whole-suite lock" in text() or p.poll() is not None:
                break
            time.sleep(0.05)
        self.assertIn("waiting for the whole-suite lock", text())
        # Held for a while longer: queued time the budget must not count.
        time.sleep(4)
        lock.release()
        self.assertEqual(p.wait(timeout=120), 0, text())
        total = time.monotonic() - began
        waited = int(re.search(r"Waited (\d+) s for the whole-suite lock; left out of the budget\.", text()).group(1))
        counted = int(re.search(r"Whole command: (\d+) s;", text()).group(1))
        self.assertGreaterEqual(waited, 3, text())
        self.assertLessEqual(counted, total - waited + 1, text())

    def test_a_failure_at_the_allowance_is_counted_as_over_it(self):
        status, out = self.run_script(env={"STUB_TIMEOUT_FORM": "1"})
        heading = "Tests that exceeded or probably exceeded their time allowance: 1 (0 exceeded, 1 probably)"
        self.assertIn(heading, out)
        self.assertNotIn("Test time allowance exceeded", out)
        self.assertIn("ProbeTests.testHung() (probably exceeded: failed at 60.000 s, the allowance rounded up "
                      "to whole minutes)", out)
        _, timing = self.run_log_and_timing()
        self.assertIn(heading, timing)
        # With a larger allowance the same failure is an ordinary one.
        status, out = self.run_script("--test-allowance-seconds", "120", env={"STUB_TIMEOUT_FORM": "1"})
        self.assertNotIn("exceeded their time allowance", out)

    def test_the_pid_comes_first(self):
        status, out = self.run_script("--dry-run")
        self.assertEqual(status, 0, out)
        self.assertRegex(out.splitlines()[0], r"^fast_tests\.sh: pid [0-9]+$")

    def test_no_wait_fails_naming_the_holder(self):
        import sys
        if TOOLS not in sys.path:
            sys.path.insert(0, TOOLS)
        import suite_guard
        self.run_script("--dry-run")  # sets self.lock
        lock = suite_guard.SuiteLock(self.lock)
        self.assertTrue(lock.acquire("a sanitized suite in another lane", ["xcodebuild"], wait=False))
        self.addCleanup(lock.release)
        status, out = self.run_script("--no-wait")
        self.assertEqual(status, 75, out)
        self.assertIn("a sanitized suite in another lane", out)
        self.assertEqual([c.split()[0] for c in self.calls()], ["build-for-testing"])


if __name__ == "__main__":
    unittest.main()
