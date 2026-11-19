"""Tests for tools/swift_migration/sanitizer_tests.sh: the mode logic (the
integer and integer-sign build flags and run) and the exit status of the
thread mode with its baseline comparison.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_sanitizer*.py'

The script is run for real, in a copy of the files it uses placed in a
temporary root (it finds its root from its own path), with stand-ins first
on PATH. Nothing is built and nothing outside the temporary directory is
written.

- xcodebuild: records its arguments and the UBSan options it was given (one
  JSON line per call in $FAKE_RECORD) and creates the test host under
  SYMROOT. For `test` it writes the report files the test asks for into the
  log_path directory of the mode (for UBSan, the fixture
  fixtures/sanitizer_sign/ubsan.probe-integer-sign with its paths moved under
  the temporary root, when $FAKE_FIXTURE is set; for TSan, the files named
  by $STUB_REPORTS), prints one passing test in the serial log format, and
  exits with $STUB_TEST_STATUS (default 0).
- otool: says the binary links both the UBSan and the TSan runtime, so the
  runtime check of every sanitizer mode passes.
- pkill: does nothing, so no real process is ever matched.
- atos: prints each address back, as atos does for an address it cannot
  name.
"""

import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS))
SIGN_FIXTURE = os.path.join(HERE, "fixtures", "sanitizer_sign", "ubsan.probe-integer-sign")
THREAD_FIXTURES = os.path.join(HERE, "fixtures", "sanitizer_thread")

COPIED = (
    "sanitizer_tests.sh",
    "sanitizer_common.sh",
    "sanitizer_summary.py",
    "test_timing.py",
    "sanitizer_ignorelist.txt",
    "sanitizer_nullability_suppressions.txt",
)

INTEGER_GROUP = "signed-integer-overflow,implicit-conversion,float-cast-overflow,integer-divide-by-zero,shift,bounds"
SIGN_CFLAGS = ("-Xclang -fsanitize=implicit-integer-sign-change "
               "-Xclang -fsanitize-recover=implicit-integer-sign-change")

FAKE_XCODEBUILD = r'''#!/bin/bash
python3 - "$@" <<'EOF'
import json, os, shutil, sys
args = sys.argv[1:]
with open(os.environ["FAKE_RECORD"], "a") as f:
    f.write(json.dumps({"args": args,
                        "ubsan": os.environ.get("TEST_RUNNER_UBSAN_OPTIONS", "")}) + "\n")
symroot = [a.split("=", 1)[1] for a in args if a.startswith("SYMROOT=")][0]
macos = os.path.join(symroot, "Development", "iTerm2.app", "Contents", "MacOS")
os.makedirs(macos, exist_ok=True)
open(os.path.join(macos, "iTerm2.debug.dylib"), "w").close()
if args and args[0] == "test":
    def log_path(variable):
        options = os.environ.get(variable, "")
        paths = [o.split("=", 1)[1] for o in options.split(":") if o.startswith("log_path=")]
        return paths[0] if paths else None
    ubsan = log_path("TEST_RUNNER_UBSAN_OPTIONS")
    if ubsan and os.environ.get("FAKE_FIXTURE"):
        with open(os.environ["FAKE_FIXTURE"]) as src, open(ubsan + ".4242", "w") as dst:
            dst.write(src.read().replace("/Users/example/iterm2", os.environ["FAKE_ROOT"]))
    tsan = log_path("TEST_RUNNER_TSAN_OPTIONS")
    for report in os.environ.get("STUB_REPORTS", "").split():
        shutil.copy(report, os.path.dirname(tsan))
    print("Test Suite 'Selected tests' started at 2026-11-20 01:08:28.898.")
    print("Test Case '-[ProbeTests testA]' started.")
    print("Test Case '-[ProbeTests testA]' passed (0.001 seconds).")
    print("** TEST SUCCEEDED ** [1.000 sec]")
    sys.stdout.flush()
    sys.exit(int(os.environ.get("STUB_TEST_STATUS", "0")))
EOF
'''

# The runtime check once read otool through `grep -q` under pipefail, where
# a write after grep quit failed with SIGPIPE; RuntimeCheckTests covers that.
FAKE_OTOOL = '''#!/bin/bash
printf '%s:\n\t@rpath/libclang_rt.ubsan_osx_dynamic.dylib (compatibility version 0.0.0)\n\t@rpath/libclang_rt.tsan_osx_dynamic.dylib (compatibility version 0.0.0)\n' "$2"
'''
FAKE_PKILL = "#!/bin/sh\nexit 1\n"
FAKE_ATOS = ("#!/bin/sh\nskip=0\nfor a in \"$@\"; do\n  if [ $skip = 1 ]; then skip=0; continue; fi\n"
             "  case \"$a\" in -o|-l|-arch) skip=1;; 0x*) echo \"$a\";; esac\ndone\n")


class ScriptTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sanitizer-tests-script-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = os.path.join(self.tmp, "root")
        tools = os.path.join(self.root, "tools", "swift_migration")
        os.makedirs(tools)
        for name in COPIED:
            shutil.copy2(os.path.join(TOOLS, name), tools)
        docs = os.path.join(self.root, "docs", "swift-migration")
        os.makedirs(docs)
        shutil.copy2(os.path.join(REPO, "docs", "swift-migration", "thread-baseline.tsv"), docs)
        for d in ("xcstrings", "sources"):
            os.makedirs(os.path.join(self.root, d))
            with open(os.path.join(self.root, d, "Localizable.xcstrings"), "w") as f:
                f.write("{}\n")
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        for name, text in (("xcodebuild", FAKE_XCODEBUILD), ("otool", FAKE_OTOOL),
                           ("pkill", FAKE_PKILL), ("atos", FAKE_ATOS)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.record = os.path.join(self.tmp, "record.jsonl")
        self.script = os.path.join(tools, "sanitizer_tests.sh")

    def run_script(self, *args, fixture=None, reports=(), test_status=0):
        """Runs the script; returns (exit status, output, recorded xcodebuild calls)."""
        env = dict(os.environ)
        env["PATH"] = self.bin + os.pathsep + env["PATH"]
        env["FAKE_RECORD"] = self.record
        env["FAKE_ROOT"] = self.root
        env.pop("FAKE_FIXTURE", None)
        if fixture:
            env["FAKE_FIXTURE"] = fixture
        env["STUB_REPORTS"] = " ".join(os.path.join(THREAD_FIXTURES, r) for r in reports)
        env["STUB_TEST_STATUS"] = str(test_status)
        env.pop("SIGNED", None)
        p = subprocess.run(["bash", self.script] + list(args), env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True, timeout=120)
        calls = []
        if os.path.exists(self.record):
            with open(self.record) as f:
                calls = [json.loads(line) for line in f]
        return p.returncode, p.stdout, calls

    @staticmethod
    def setting(call, name):
        values = [a.split("=", 1)[1] for a in call["args"] if a.startswith(name + "=")]
        assert len(values) == 1, (name, values)
        return values[0]


class IntegerModeTests(ScriptTestCase):
    """The integer and integer-sign modes: build flags and a run."""

    def test_integer_sign_build_flags(self):
        status, out, calls = self.run_script("integer-sign", "--build-only")
        self.assertEqual(status, 0, out)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["args"][0], "build-for-testing")
        cflags = self.setting(calls[0], "OTHER_CFLAGS")
        self.assertIn("-fsanitize=" + INTEGER_GROUP + " -fsanitize-recover=" + INTEGER_GROUP, cflags)
        self.assertIn(SIGN_CFLAGS, cflags)
        self.assertIn("-fsanitize-ignorelist=", cflags)
        # The runtime is the same UBSan runtime the integer group links.
        self.assertEqual(self.setting(calls[0], "OTHER_LDFLAGS"), "$(inherited) -fsanitize=" + INTEGER_GROUP)
        # Its own build directory, so the integer mode's build is not rebuilt.
        self.assertEqual(self.setting(calls[0], "SYMROOT"),
                         os.path.join(self.root, "tmp", "sanitizers", "integer-sign", "Build"))

    def test_integer_mode_is_unchanged(self):
        status, out, calls = self.run_script("integer", "--build-only")
        self.assertEqual(status, 0, out)
        cflags = self.setting(calls[0], "OTHER_CFLAGS")
        self.assertIn("-fsanitize=" + INTEGER_GROUP, cflags)
        self.assertNotIn("implicit-integer-sign-change", cflags)
        self.assertEqual(self.setting(calls[0], "SYMROOT"),
                         os.path.join(self.root, "tmp", "sanitizers", "integer", "Build"))

    def test_integer_sign_run_collects_and_summarizes(self):
        status, out, calls = self.run_script("integer-sign", "ModernTests/SignProbeTests", fixture=SIGN_FIXTURE)
        self.assertEqual(status, 0, out)
        self.assertEqual([c["args"][0] for c in calls], ["build-for-testing", "test"])
        self.assertIn("-only-testing:ModernTests/SignProbeTests", calls[1]["args"])
        ubsan = calls[1]["ubsan"].split(":")
        self.assertIn("halt_on_error=0", ubsan)
        self.assertIn("report_error_type=1", ubsan)
        self.assertTrue(any(o.startswith("log_path=" + os.path.join(self.root, "tmp", "sanitizers", "runs",
                                                                    "integer-sign-"))
                            for o in ubsan), ubsan)
        self.assertIn("Reports: 4 at 4 location(s): 4 in scope, 0 in other code.", out)
        self.assertIn("implicit-integer-sign-change", out)
        runs = os.path.join(self.root, "tmp", "sanitizers", "runs")
        (run_dir,) = os.listdir(runs)
        with open(os.path.join(runs, run_dir, "summary.txt")) as f:
            summary = f.read()
        self.assertIn("Sign-change check: -fsanitize=implicit-integer-sign-change (through -Xclang)", summary)
        self.assertIn("Reports: 4 at 4 location(s)", summary)

    def test_unknown_mode_is_a_usage_error(self):
        status, out, calls = self.run_script("integer-signs", "--build-only")
        self.assertEqual(status, 2)
        self.assertEqual(calls, [])


class CollectTests(ScriptTestCase):
    """--collect applies to the nullability and thread modes only."""

    def test_collect_is_refused_for_integer_sign(self):
        status, out, calls = self.run_script("integer-sign", "--collect", "--build-only")
        self.assertEqual(status, 2)
        self.assertEqual(calls, [])

    def test_collect_is_refused_for_integer_and_plain(self):
        for mode in ("integer", "plain"):
            status, out, calls = self.run_script(mode, "--collect", "ModernTests/ProbeTests")
            self.assertEqual(status, 2, out)
            self.assertIn("--collect applies to the nullability and thread modes", out)
            self.assertEqual(calls, [])


class ThreadModeStatusTests(ScriptTestCase):
    """The thread mode exits 0 only if the tests passed and every report is
    in the baseline (docs/swift-migration/thread-baseline.tsv)."""

    def test_baseline_report_only_passes(self):
        status, out, _ = self.run_script("thread", "ModernTests/ProbeTests", reports=["tsan.metal"])
        self.assertEqual(status, 0, out)
        self.assertIn("Baseline: ", out)
        self.assertIn("Verdict: PASS: 0 report(s) outside the baseline, 0 unmatchable; 1 accepted.", out)

    def test_report_outside_baseline_fails(self):
        status, out, _ = self.run_script("thread", "ModernTests/ProbeTests",
                                         reports=["tsan.flag-across-writes-other-build"])
        self.assertEqual(status, 1, out)
        self.assertIn("Verdict: FAIL: 2 report(s) outside the baseline", out)
        self.assertIn("error: the thread sanitizer reported races outside the baseline", out)

    def test_unsymbolized_report_fails(self):
        status, out, _ = self.run_script("thread", "ModernTests/ProbeTests", reports=["tsan.metal-unsymbolized"])
        self.assertEqual(status, 1, out)
        self.assertIn("Unmatchable (these fail): 1 group(s)", out)

    def test_collect_does_not_fail_on_reports(self):
        status, out, _ = self.run_script("thread", "--collect", "ModernTests/ProbeTests",
                                         reports=["tsan.flag-across-writes-other-build"])
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict (--collect, does not fail the run): FAIL", out)

    def test_test_failure_status_is_kept(self):
        status, out, _ = self.run_script("thread", "ModernTests/ProbeTests", reports=["tsan.metal"], test_status=65)
        self.assertEqual(status, 65, out)

    def test_no_reports_passes(self):
        status, out, _ = self.run_script("thread", "ModernTests/ProbeTests")
        self.assertEqual(status, 0, out)
        self.assertIn("Verdict: PASS", out)


# An otool that writes its lines one at a time, the matching line first, then
# about a megabyte more: far more than a pipe holds, so once a reader that
# stopped at the first match (grep -q) has gone, the later writes fail with
# SIGPIPE every time. This is what exposed the race in san_check_runtime.
SLOW_OTOOL = '''#!/bin/bash
echo "$2:"
echo "	@rpath/libclang_rt.%s_osx_dynamic.dylib (compatibility version 0.0.0)"
for i in $(seq 1 20000); do
    echo "	/usr/lib/libfiller$i.dylib (compatibility version 1.0.0, current version 1.0.0)"
done
'''


class RuntimeCheckTests(ScriptTestCase):
    """The runtime checks of sanitizer_common.sh read all of otool's output:
    a check must not depend on whether otool finished writing before grep
    found its line (pipefail would turn otool's SIGPIPE into the pipeline's
    status)."""

    def use_otool(self, runtime):
        path = os.path.join(self.bin, "otool")
        with open(path, "w") as f:
            f.write(SLOW_OTOOL % runtime)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def test_runtime_found_first_is_found(self):
        self.use_otool("tsan")
        status, out, _ = self.run_script("thread", "--build-only")
        self.assertEqual(status, 0, out)
        self.assertIn("Runtime check: iTerm2.debug.dylib links libclang_rt.tsan_osx_dynamic.dylib", out)

    def test_plain_build_linking_a_runtime_is_refused(self):
        self.use_otool("ubsan")
        status, out, _ = self.run_script("plain", "--build-only")
        self.assertEqual(status, 1, out)
        self.assertIn("links a sanitizer runtime: libclang_rt.ubsan_osx_dynamic.dylib", out)


if __name__ == "__main__":
    unittest.main()
