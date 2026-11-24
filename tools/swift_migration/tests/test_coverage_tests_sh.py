"""Tests for the build and worker options of
tools/swift_migration/coverage_tests.sh: --jobs (xcodebuild -jobs) and
--workers, with the two-worker default of --parallel (the cap of
tools/run_tests.expect -parallel).

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_coverage_tests_sh.py

The script is run for real, in a copy of the files it uses placed in a
temporary root, with stand-ins first on PATH. Nothing is built and nothing
outside the temporary directory is written. Only the xcodebuild arguments
are checked: the stand-in test step writes no profile, so a run that tests
goes on to fail for want of one, which these tests do not look at.

- xcodebuild: appends its arguments (one JSON list per call) to
  $FAKE_RECORD and creates the test host under SYMROOT.
- xcrun: --find prints a path; anything else prints a version line.
- otool: -l shows a coverage mapping section, -L lists no sanitizer runtime.
- pkill: does nothing, so no real process is ever matched.
- git: lists no files (the temporary root is not a repository, and no
  repository is made there).
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

COPIED = ("coverage_tests.sh", "sanitizer_common.sh", "coverage_report.py", "sanitizer_ignorelist.txt")

FAKE_XCODEBUILD = r'''#!/bin/bash
python3 - "$@" <<'EOF'
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_RECORD"], "a") as f:
    f.write(json.dumps(args) + "\n")
symroot = [a.split("=", 1)[1] for a in args if a.startswith("SYMROOT=")][0]
macos = os.path.join(symroot, "Development", "iTerm2.app", "Contents", "MacOS")
os.makedirs(macos, exist_ok=True)
open(os.path.join(macos, "iTerm2.debug.dylib"), "w").close()
EOF
'''
FAKE_XCRUN = '#!/bin/sh\nif [ "$1" = --find ]; then echo /usr/bin/true; else echo "LLVM version 0"; fi\n'
FAKE_OTOOL = ('#!/bin/sh\nif [ "$1" = -l ]; then echo "  sectname __llvm_covmap"; '
              'else echo "$2:"; echo "\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)"; fi\n')
FAKE_PKILL = "#!/bin/sh\nexit 1\n"
FAKE_GIT = "#!/bin/sh\nexit 0\n"


class CoverageOptionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="coverage-tests-script-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = os.path.join(self.tmp, "root")
        tools = os.path.join(self.root, "tools", "swift_migration")
        os.makedirs(tools)
        for name in COPIED:
            shutil.copy2(os.path.join(TOOLS, name), tools)
        for d in ("xcstrings", "sources"):
            os.makedirs(os.path.join(self.root, d))
            with open(os.path.join(self.root, d, "Localizable.xcstrings"), "w") as f:
                f.write("{}\n")
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        for name, text in (("xcodebuild", FAKE_XCODEBUILD), ("xcrun", FAKE_XCRUN), ("otool", FAKE_OTOOL),
                           ("pkill", FAKE_PKILL), ("git", FAKE_GIT)):
            path = os.path.join(self.bin, name)
            with open(path, "w") as f:
                f.write(text)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        self.record = os.path.join(self.tmp, "record.jsonl")
        self.script = os.path.join(tools, "coverage_tests.sh")

    def run_script(self, *args):
        """Runs the script; returns (exit status, output, recorded xcodebuild calls)."""
        env = dict(os.environ)
        env["PATH"] = self.bin + os.pathsep + env["PATH"]
        env["FAKE_RECORD"] = self.record
        env["COVERAGE_IDLE_SECONDS"] = "1"
        env.pop("SIGNED", None)
        p = subprocess.run(["bash", self.script] + list(args), env=env, cwd=self.tmp,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True, timeout=120)
        calls = []
        if os.path.exists(self.record):
            with open(self.record) as f:
                calls = [json.loads(line) for line in f]
        return p.returncode, p.stdout, calls

    @staticmethod
    def follows(args, flag):
        return [args[i + 1] for i, a in enumerate(args) if a == flag and i + 1 < len(args)]

    def test_jobs_limits_the_build(self):
        status, out, calls = self.run_script("--build-only", "--jobs", "4")
        self.assertEqual(status, 0, out)
        (build,) = calls
        self.assertEqual(build[0], "build-for-testing")
        self.assertEqual(self.follows(build, "-jobs"), ["4"])

    def test_jobs_reaches_the_test_step(self):
        # `xcodebuild test` brings the build up to date, so it is limited too.
        _, out, calls = self.run_script("--jobs", "4", "ModernTests/ProbeTests")
        self.assertEqual([c[0] for c in calls], ["build-for-testing", "test"], out)
        self.assertEqual(self.follows(calls[1], "-jobs"), ["4"])

    def test_no_jobs_by_default(self):
        status, out, calls = self.run_script("--build-only")
        self.assertEqual(status, 0, out)
        self.assertNotIn("-jobs", calls[0])

    def test_parallel_defaults_to_two_workers(self):
        _, out, calls = self.run_script("--parallel", "ModernTests/ProbeTests")
        test = calls[-1]
        self.assertEqual(test[0], "test", out)
        self.assertEqual(self.follows(test, "-parallel-testing-enabled"), ["YES"])
        self.assertEqual(self.follows(test, "-parallel-testing-worker-count"), ["2"])
        self.assertEqual(self.follows(test, "-maximum-parallel-testing-workers"), ["2"])

    def test_workers_changes_the_count(self):
        _, out, calls = self.run_script("--parallel", "--workers", "3", "ModernTests/ProbeTests")
        test = calls[-1]
        self.assertEqual(test[0], "test", out)
        self.assertEqual(self.follows(test, "-parallel-testing-worker-count"), ["3"])
        self.assertEqual(self.follows(test, "-maximum-parallel-testing-workers"), ["3"])

    def test_serial_run_has_no_worker_count(self):
        _, out, calls = self.run_script("ModernTests/ProbeTests")
        test = calls[-1]
        self.assertEqual(test[0], "test", out)
        self.assertEqual(self.follows(test, "-parallel-testing-enabled"), ["NO"])
        self.assertNotIn("-parallel-testing-worker-count", test)

    def test_usage_errors(self):
        for args in (("--workers", "2", "ModernTests/A"), ("--parallel", "--workers", "0"),
                     ("--parallel", "--workers"), ("--jobs", "x"), ("--jobs",),
                     ("--build-only", "--parallel", "--workers", "2")):
            status, out, calls = self.run_script(*args)
            self.assertEqual(status, 2, (args, out))
            self.assertEqual(calls, [], args)


if __name__ == "__main__":
    unittest.main()
