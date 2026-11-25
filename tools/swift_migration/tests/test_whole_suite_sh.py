"""Tests for tools/swift_migration/whole_suite.sh: tools/run_tests.expect
under the whole-suite lock.

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_whole_suite_sh.py

RUN_TESTS_EXPECT names a stand-in for tools/run_tests.expect that records
its arguments and whether it ran under the lock, and exits with
$STUB_STATUS. The lock is a file in the test's temporary directory
(SWIFT_MIGRATION_SUITE_LOCK), never the machine's real one. Nothing is
built or tested.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
SCRIPT = os.path.join(TOOLS, 'whole_suite.sh')
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

import suite_guard  # noqa: E402

STUB = '''#!/bin/sh
printf '%s\\n' "$@" > "$STUB_DIR/args"
printf '%s' "${SWIFT_MIGRATION_SUITE_LOCK_HELD:-}" > "$STUB_DIR/held"
pwd > "$STUB_DIR/pwd"
ps -o command= -p $PPID > "$STUB_DIR/parent"
if [ -n "${STUB_STALL:-}" ]; then
  # As run_tests.expect's watchdog does: a stall report, then exit 1.
  mkdir -p tmp && echo stacks > "tmp/test-stall-$STUB_STALL.txt"
  echo "*** No test output for 300 seconds. The run looks hung. ***"
  exit 1
fi
if [ -n "${STUB_HOLD:-}" ]; then
  while [ ! -e "$STUB_DIR/release" ] && [ -d "$STUB_DIR" ]; do sleep 0.05; done
fi
exit "${STUB_STATUS:-0}"
'''


class WholeSuiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='whole_suite_test.'))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.stub = os.path.join(self.tmp, 'run_tests.expect')
        with open(self.stub, 'w') as f:
            f.write(STUB)
        os.chmod(self.stub, 0o755)
        self.lock = os.path.join(self.tmp, 'locks', 'whole-suite.lock')
        self.env = dict(os.environ)
        self.env.pop(suite_guard.HELD_ENV, None)
        self.env.update({'RUN_TESTS_EXPECT': self.stub, 'STUB_DIR': self.tmp,
                         'SWIFT_MIGRATION_SUITE_LOCK': self.lock})

    def stop(self, p):
        """Ends a whole_suite.sh started in the background: SIGTERM, which
        it passes on to its run (SIGKILL would orphan the run), and the
        release file for the stand-in."""
        open(os.path.join(self.tmp, 'release'), 'w').close()
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=30)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

    def run_script(self, *args, **env):
        e = dict(self.env)
        e.update(env)
        p = subprocess.run(['bash', SCRIPT] + list(args), env=e, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, universal_newlines=True, timeout=120)
        return p.returncode, p.stdout

    def read(self, name):
        with open(os.path.join(self.tmp, name)) as f:
            return f.read()

    def test_runs_the_parallel_whole_suite_under_the_lock(self):
        status, out = self.run_script()
        self.assertEqual(status, 0, out)
        self.assertEqual(self.read('args'), '-parallel\n')
        self.assertTrue(self.read('held').endswith(':' + self.lock), out)
        self.assertEqual(self.read('pwd').strip(), os.path.realpath(os.path.dirname(os.path.dirname(TOOLS))))
        self.assertRegex(out, r'(?m)^whole_suite\.sh: pid [0-9]+$')
        # The lock process is told this checkout's build directory, for its
        # test hosts, and where run_tests.expect writes its stall reports.
        root = os.path.realpath(os.path.dirname(os.path.dirname(TOOLS)))
        parent = self.read('parent')
        self.assertIn('--host-prefix %s/Build' % root, parent)
        self.assertIn('--stall-reports %s/tmp/test-stall-*.txt' % root, parent)
        self.assertEqual(subprocess.run([sys.executable, '-B', os.path.join(TOOLS, 'suite_guard.py'), 'status'],
                                        env=self.env, stdout=subprocess.DEVNULL).returncode, 0)

    def test_serial_runs_the_bare_target(self):
        status, out = self.run_script('--serial')
        self.assertEqual(status, 0, out)
        self.assertEqual(self.read('args'), 'ModernTests\n')

    def test_the_status_passes_through(self):
        status, out = self.run_script(STUB_STATUS='65')
        self.assertEqual(status, 65, out)

    def test_a_stall_of_run_tests_expect_is_status_124(self):
        token = 'whole-suite-test-%d' % os.getpid()
        report = os.path.join(os.path.dirname(os.path.dirname(TOOLS)), 'tmp', 'test-stall-%s.txt' % token)
        self.addCleanup(lambda: os.path.exists(report) and os.remove(report))
        status, out = self.run_script(STUB_STALL=token)
        self.assertEqual(status, 124, out)
        self.assertIn("the command's stall watchdog stopped the run", out)
        self.assertIn(report, out)

    def test_a_failure_without_a_stall_report_keeps_its_status(self):
        status, out = self.run_script(STUB_STATUS='1')
        self.assertEqual(status, 1, out)
        self.assertNotIn('stall watchdog', out)

    def test_test_names_are_refused(self):
        status, out = self.run_script('ModernTests/FooTests')
        self.assertEqual(status, 2, out)
        self.assertIn('takes no test names', out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'args')))

    def test_no_wait_fails_naming_the_holder(self):
        lock = suite_guard.SuiteLock(self.lock)
        self.assertTrue(lock.acquire('a sanitized suite elsewhere', ['xcodebuild'], wait=False))
        self.addCleanup(lock.release)
        status, out = self.run_script('--no-wait')
        self.assertEqual(status, suite_guard.EXIT_LOCK_BUSY, out)
        self.assertIn('a sanitized suite elsewhere', out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'args')))

    def test_two_runs_serialize(self):
        e = dict(self.env)
        e['STUB_HOLD'] = '1'
        first = subprocess.Popen(['bash', SCRIPT], env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(self.stop, first)
        end = time.monotonic() + 60
        while not os.path.exists(os.path.join(self.tmp, 'args')) and time.monotonic() < end:
            time.sleep(0.05)
        os.remove(os.path.join(self.tmp, 'args'))
        out_path = os.path.join(self.tmp, 'second.out')
        with open(out_path, 'w') as out:
            second = subprocess.Popen(['bash', SCRIPT], env=self.env, stdout=out, stderr=subprocess.STDOUT)
        self.addCleanup(self.stop, second)
        end = time.monotonic() + 60
        while 'waiting for the whole-suite lock' not in self.read('second.out') and time.monotonic() < end:
            time.sleep(0.05)
        self.assertIn('waiting for the whole-suite lock', self.read('second.out'))
        # The holder is the first run's lock process (whole_suite.sh stays
        # to look for run_tests.expect's stall report afterwards), named by
        # its label.
        self.assertIn('(running)', self.read('second.out'))
        self.assertIn('whole_suite.sh: run_tests.expect -parallel', self.read('second.out'))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'args')))
        open(os.path.join(self.tmp, 'release'), 'w').close()
        self.assertEqual(first.wait(timeout=60), 0)
        self.assertEqual(second.wait(timeout=60), 0, self.read('second.out'))
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'args')))


if __name__ == '__main__':
    unittest.main()
