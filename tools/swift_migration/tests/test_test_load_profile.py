"""Tests for tools/swift_migration/test_load_profile.py.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests

Expected values were worked out by hand from the synthetic samples below.
No test starts a test host or signals any process but the stand-in
commands they start themselves.
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from types import SimpleNamespace

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import test_load_profile as tlp  # noqa: E402

HOST = '/x/lane/Build/Development/iTerm2.app/Contents/MacOS/iTerm2'
TEST_ARGS = [HOST, '-suite', 'iterm2-tests', '-NSTreatUnknownArgumentsAsOpen', 'NO']
# The owner's own development build, started by `make run` in the checkout.
OWNER_ARGS = [HOST, '-suite', 'iterm2-alt']


class ParseEventTests(unittest.TestCase):
    def test_serial_lines(self):
        self.assertEqual(tlp.parse_event("Test Suite 'FooTests' started at 2026-11-23 12:00:00.000."),
                         ('suite_start', 'FooTests'))
        self.assertEqual(tlp.parse_event("Test Case '-[ModernTests.FooTests testBar]' started."),
                         ('test_start', 'FooTests', 'testBar'))
        self.assertEqual(tlp.parse_event("Test Case '-[ModernTests.FooTests testBar]' passed (1.250 seconds)."),
                         ('test_end', 'FooTests', 'testBar', 'passed', 1.25))
        self.assertEqual(tlp.parse_event("Test Case '-[FooTests testBar]' failed (0.002 seconds)."),
                         ('test_end', 'FooTests', 'testBar', 'failed', 0.002))
        self.assertEqual(tlp.parse_event("Test Suite 'FooTests' failed at 2026-11-23 12:00:01.000."),
                         ('suite_end', 'FooTests'))

    def test_escape_sequences_and_carriage_returns_are_ignored(self):
        self.assertEqual(tlp.parse_event("\x1b[1mTest Case '-[ModernTests.A testB]' started.\r"),
                         ('test_start', 'A', 'testB'))

    def test_bundle_and_all_tests_suites_are_not_classes(self):
        self.assertIsNone(tlp.parse_event("Test Suite 'All tests' started at 2026-11-23 12:00:00.000."))
        self.assertIsNone(tlp.parse_event("Test Suite 'ModernTests.xctest' started at 2026-11-23 12:00:00.000."))
        self.assertIsNone(tlp.parse_event("Test Suite 'Selected tests' passed at 2026-11-23 12:00:00.000."))

    def test_other_lines(self):
        self.assertIsNone(tlp.parse_event('CompileSwift normal arm64 Foo.swift'))
        # A parallel result line has no start line and is not attributed.
        self.assertIsNone(tlp.parse_event("Test case 'FooTests.testBar()' passed on 'Clone 1' (0.1 seconds)"))


def sample(t, bucket, cpu, threads=10, running=1, rss=100 << 20, hosts=(1,), load=5.0):
    return {'t': t, 'bucket': bucket, 'cpu': cpu, 'threads': threads, 'running': running, 'rss': rss,
            'hosts': list(hosts), 'load': load}


class AnalyzeTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='tlp-test-')

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, lines, samples, interval=0.1):
        with open(os.path.join(self.dir, 'output.log'), 'w') as f:
            for t, text in lines:
                f.write('%.6f\t%s\n' % (t, text))
        with open(os.path.join(self.dir, 'samples.jsonl'), 'w') as f:
            for s in samples:
                f.write(json.dumps(s) + '\n')
        with open(os.path.join(self.dir, 'meta.json'), 'w') as f:
            json.dump({'interval': interval}, f)

    def test_attribution_of_cpu_threads_and_leftovers(self):
        # The class is set up from 100.0 to 100.2 (0.1 CPU s). testA runs
        # 100.2 to 100.6 on four cores and leaves 5 threads; testB runs
        # 100.6 to 100.8 nearly idle.
        start = "Test Case '-[ModernTests.Foo testA]' started."
        end = "Test Case '-[ModernTests.Foo testA]' passed (0.400 seconds)."
        startb = "Test Case '-[ModernTests.Foo testB]' started."
        endb = "Test Case '-[ModernTests.Foo testB]' passed (0.200 seconds)."
        self.write(
            [(100.0, "Test Suite 'Foo' started at x."), (100.1, 'noise'), (100.2, start), (100.6, end),
             (100.6001, startb), (100.8, endb), (100.9, "Test Suite 'Foo' passed at y.")],
            [sample(100.0, tlp.NO_TEST, 1.0),
             sample(100.1, 'Foo (outside tests)', 1.05),
             sample(100.2, 'Foo (outside tests)', 1.1),          # taken for testA's start line
             sample(100.3, 'Foo/testA', 1.5, threads=20, running=4),
             sample(100.4, 'Foo/testA', 1.9, threads=25, running=5),
             sample(100.5, 'Foo/testA', 2.3, threads=22, running=3),
             sample(100.6, 'Foo/testA', 2.7, threads=15, running=1),  # testA's result line
             sample(100.6001, 'Foo (outside tests)', 2.7, threads=15),  # testB's start line
             sample(100.7, 'Foo/testB', 2.71, threads=15),
             sample(100.8, 'Foo/testB', 2.72, threads=15),
             sample(100.9, 'Foo (outside tests)', 2.73, threads=15)])
        profile, text = tlp.analyze(self.dir)
        a = profile.stats['Foo/testA']
        self.assertAlmostEqual(a.cpu, 1.6)
        self.assertAlmostEqual(a.wall(), 0.4)
        self.assertAlmostEqual(a.peak_pct, 400.0)
        self.assertEqual(a.peak_threads, 25)
        self.assertEqual(a.peak_running, 5)
        self.assertEqual(a.threads_start, 10)
        self.assertEqual(a.threads_end, 15)
        self.assertEqual(a.thread_delta(), 5)
        self.assertEqual(a.status, 'passed')
        self.assertEqual(a.reported, 0.4)
        b = profile.stats['Foo/testB']
        self.assertAlmostEqual(b.cpu, 0.02)
        self.assertEqual(b.thread_delta(), 0)
        outside = profile.stats['Foo (outside tests)']
        self.assertAlmostEqual(outside.cpu, 0.1 + 0.0 + 0.01)
        self.assertIn('Foo/testA', text)
        with open(os.path.join(self.dir, 'profile.tsv')) as f:
            rows = [line.rstrip('\n').split('\t') for line in f]
        self.assertEqual(rows[0], tlp.TSV_HEADER)
        self.assertEqual(rows[1][0], 'Foo/testA')
        self.assertEqual(rows[1][5], '4.00')  # cores
        self.assertEqual(rows[1][9], '5')     # thr+

    def test_short_intervals_do_not_set_the_peak(self):
        # 0.01 CPU s in 0.001 s would read as 1000%; the interval is too short.
        self.write([(1.0, "Test Case '-[A b]' started."), (1.201, "Test Case '-[A b]' passed (0.2 seconds).")],
                   [sample(1.0, tlp.NO_TEST, 0.0), sample(1.1, 'A/b', 0.05), sample(1.2, 'A/b', 0.1),
                    sample(1.201, 'A/b', 0.11)])
        profile, _ = tlp.analyze(self.dir)
        self.assertAlmostEqual(profile.stats['A/b'].peak_pct, 50.0)
        self.assertAlmostEqual(profile.stats['A/b'].cpu, 0.11)

    def test_a_host_restart_starts_a_new_baseline(self):
        # The host crashed and a new one (pid 2) started with its own CPU
        # clock: the drop must not count, nor the jump between hosts.
        self.write([(1.0, "Test Case '-[A b]' started.")],
                   [sample(1.0, tlp.NO_TEST, 50.0), sample(1.1, 'A/b', 50.5),
                    sample(1.2, 'A/b', 0.2, hosts=(2,)), sample(1.3, 'A/b', 0.4, hosts=(2,)),
                    sample(1.4, 'A/b', 0.0, hosts=())])
        profile, _ = tlp.analyze(self.dir)
        self.assertAlmostEqual(profile.stats['A/b'].cpu, 0.5 + 0.2)

    def test_a_descendant_exiting_does_not_subtract(self):
        self.write([(1.0, "Test Case '-[A b]' started.")],
                   [sample(1.0, tlp.NO_TEST, 5.0), sample(1.1, 'A/b', 6.0), sample(1.2, 'A/b', 5.5),
                    sample(1.3, 'A/b', 5.7)])
        profile, _ = tlp.analyze(self.dir)
        self.assertAlmostEqual(profile.stats['A/b'].cpu, 1.0 + 0.2)

    def test_cores_is_left_empty_for_very_short_tests(self):
        self.write([(1.0, "Test Case '-[A b]' started."), (1.002, "Test Case '-[A b]' passed (0.001 seconds).")],
                   [sample(1.0, tlp.NO_TEST, 0.0), sample(1.002, 'A/b', 0.002)])
        tlp.analyze(self.dir)
        with open(os.path.join(self.dir, 'profile.tsv')) as f:
            row = [line.rstrip('\n').split('\t') for line in f][1]
        self.assertEqual(row[0], 'A/b')
        self.assertEqual(row[5], '')

    def test_summary_lists_thread_leavers(self):
        self.write([(1.0, "Test Case '-[A leaky]' started."), (1.2, "Test Case '-[A leaky]' passed (0.2 seconds).")],
                   [sample(1.0, tlp.NO_TEST, 0.0, threads=10), sample(1.1, 'A/leaky', 0.0, threads=30),
                    sample(1.2, 'A/leaky', 0.0, threads=30)])
        _, text = tlp.analyze(self.dir)
        self.assertIn('Tests that ended with more threads than they started with (1):', text)


class FakeProc:
    """A stand-in for Libproc: a process table. Entries in `late` join the
    table after the first call to pids(), as processes started during a run
    do."""

    def __init__(self, table, late=None):
        # pid -> (path, ppid, (cpu, threads, running, rss)[, argv or None])
        # With no argv, a test host's arguments; None: unreadable.
        self.table = table
        self.late = late or {}
        self.listed = False

    def pids(self):
        if self.listed and self.late:
            self.table.update(self.late)
            self.late = {}
        self.listed = True
        return list(self.table)

    def args(self, pid):
        if pid not in self.table:
            return None
        entry = self.table[pid]
        return entry[3] if len(entry) > 3 else TEST_ARGS

    def path(self, pid):
        return self.table[pid][0] if pid in self.table else None

    def ppid(self, pid):
        return self.table[pid][1] if pid in self.table else None

    def task(self, pid):
        return self.table[pid][2] if pid in self.table else None


class SamplerTests(unittest.TestCase):
    def test_hosts_by_path_and_descendants_cpu(self):
        table = {
            10: (HOST, 1, (2.0, 30, 3, 500)),
            11: ('/bin/zsh', 10, (0.5, 1, 1, 7)),
            12: ('/usr/bin/tmux', 11, (0.25, 2, 0, 7)),
            # The owner's iTerm2, and a test host in another checkout.
            20: ('/Applications/iTerm.app/Contents/MacOS/iTerm2', 1, (99.0, 50, 9, 9)),
            21: ('/x/other/Build/Development/iTerm2.app/Contents/MacOS/iTerm2', 1, (99.0, 50, 9, 9)),
            22: ('/bin/zsh', 20, (99.0, 1, 1, 9)),
            # Under the prefix but not a test host executable.
            30: ('/x/lane/Build/Development/iTerm2.app/Contents/MacOS/iTermServer', 1, (99.0, 1, 1, 9)),
        }
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']  # no realpath for the made-up directory
        s = sampler.sample()
        self.assertEqual(s['hosts'], [10])
        self.assertAlmostEqual(s['cpu'], 2.75)
        self.assertEqual(s['threads'], 30)   # the host's own threads
        self.assertEqual(s['running'], 4)    # the host's and its descendants' running threads
        self.assertEqual(s['rss'], 500)

    def test_a_host_seen_before_its_exec_is_found_after_it(self):
        # launchd starts a test host as xpcproxy, which then execs the app
        # under the same pid: a path read before the exec must not stick.
        table = {10: ('/usr/libexec/xpcproxy', 1, (0.0, 1, 0, 1))}
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']
        now = [100.0]
        sampler.clock = lambda: now[0]
        self.assertEqual(sampler.sample()['hosts'], [])
        table[10] = (HOST, 1, (1.0, 20, 1, 1))
        now[0] += tlp.Sampler.PATH_RECHECK_SECONDS + 0.01
        self.assertEqual(sampler.sample()['hosts'], [10])

    def test_the_owners_development_build_is_not_a_test_host(self):
        # Same path as a test host under Build/, but its own suite.
        table = {10: (HOST, 1, (2.0, 30, 3, 500), OWNER_ARGS)}
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']
        self.assertEqual(sampler.sample()['hosts'], [])
        self.assertFalse(sampler.is_test_host(10))

    def test_a_process_whose_arguments_cannot_be_read_is_not_a_test_host(self):
        table = {10: (HOST, 1, (2.0, 30, 3, 500), None)}
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']
        self.assertEqual(sampler.sample()['hosts'], [])
        self.assertFalse(sampler.is_test_host(10))

    def test_a_test_host_older_than_the_run_is_not_sampled(self):
        table = {10: (HOST, 1, (2.0, 30, 3, 500))}
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']
        self.assertEqual(sampler.sample()['hosts'], [10])
        sampler = tlp.Sampler(['/x/lane/Build'], proc=FakeProc(table))
        sampler.prefixes = ['/x/lane/Build/']
        sampler.exclude_existing()
        self.assertEqual(sampler.sample()['hosts'], [])
        self.assertFalse(sampler.is_test_host(10))

    def test_suite_argument_must_be_the_pair(self):
        self.assertTrue(tlp.has_test_host_suite(TEST_ARGS))
        self.assertFalse(tlp.has_test_host_suite(OWNER_ARGS))
        self.assertFalse(tlp.has_test_host_suite([HOST, 'iterm2-tests', '-suite']))
        self.assertFalse(tlp.has_test_host_suite(None))
        self.assertFalse(tlp.has_test_host_suite([]))

    def test_parse_procargs2(self):
        raw = (3).to_bytes(4, sys.byteorder) + b'/bin/exe\0\0\0\0/bin/exe\0-suite\0iterm2-tests\0FOO=bar\0'
        self.assertEqual(tlp.parse_procargs2(raw), ['/bin/exe', '-suite', 'iterm2-tests'])
        self.assertIsNone(tlp.parse_procargs2(b'\1\0'))
        self.assertIsNone(tlp.parse_procargs2((5).to_bytes(4, sys.byteorder) + b'/bin/exe\0a\0'))

    def test_is_test_host_path(self):
        self.assertTrue(tlp.is_test_host_path(HOST, ['/x/lane/Build/']))
        self.assertFalse(tlp.is_test_host_path(HOST, ['/x/lane/Bui/']))
        self.assertFalse(tlp.is_test_host_path(None, ['/x/lane/Build/']))
        self.assertFalse(tlp.is_test_host_path('/x/lane/Build/iTerm2', ['/x/lane/Build/']))

    def test_real_libproc_reads_this_process(self):
        proc = tlp.Libproc()
        self.assertIn(os.getpid(), proc.pids())
        self.assertEqual(proc.ppid(os.getpid()), os.getppid())
        cpu, threads, running, rss = proc.task(os.getpid())
        self.assertGreater(threads, 0)
        self.assertGreater(rss, 0)
        self.assertGreaterEqual(cpu, 0.0)
        self.assertTrue(proc.path(os.getpid()))
        args = proc.args(os.getpid())
        self.assertTrue(args)
        self.assertEqual(args[-1], sys.argv[-1])


class RunTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='tlp-run-')

    def tearDown(self):
        shutil.rmtree(self.dir)

    def args(self, **kw):
        base = dict(interval=0.05, timeout=0, stall_seconds=0, top=10)
        base.update(kw)
        return SimpleNamespace(**base)

    def test_runs_a_command_and_profiles_its_lines(self):
        script = ("import sys,time\n"
                  "print(\"Test Suite 'A' started at x.\")\n"
                  "print(\"Test Case '-[ModernTests.A testB]' started.\", flush=True)\n"
                  "time.sleep(0.2)\n"
                  "print(\"Test Case '-[ModernTests.A testB]' passed (0.200 seconds).\")\n"
                  "print(\"Test Suite 'A' passed at y.\")\n")
        sampler = tlp.Sampler(['/nonexistent'], proc=FakeProc({}))
        runner = tlp.Runner(self.args(), sampler, self.dir)
        status = runner.run([sys.executable, '-c', script])
        self.assertEqual(status, 0)
        profile, _ = tlp.analyze(self.dir)
        b = profile.stats['A/testB']
        self.assertEqual(b.status, 'passed')
        self.assertGreaterEqual(b.wall(), 0.15)
        with open(os.path.join(self.dir, 'samples.jsonl')) as f:
            buckets = [json.loads(line)['bucket'] for line in f]
        self.assertIn('A/testB', buckets)

    def test_stall_kills_the_command(self):
        sampler = tlp.Sampler(['/nonexistent'], proc=FakeProc({}))
        runner = tlp.Runner(self.args(stall_seconds=1), sampler, self.dir)
        status = runner.run([sys.executable, '-c', 'import time; time.sleep(60)'])
        self.assertEqual(status, 1)
        self.assertIsNotNone(runner.proc.poll())

    def test_only_test_hosts_started_during_the_run_are_killed(self):
        # 10: a test host that was running before the run. 11: the owner's
        # development build, started during the run. 12: a host whose
        # arguments cannot be read. 13: a test host started during the run,
        # the only one that may be signalled. os.kill is replaced, so
        # nothing is really signalled.
        table = {10: (HOST, 1, (1.0, 5, 0, 1))}
        late = {11: (HOST, 1, (1.0, 5, 0, 1), OWNER_ARGS),
                12: (HOST, 1, (1.0, 5, 0, 1), None),
                13: (HOST, 1, (1.0, 5, 0, 1))}
        proc = FakeProc(table, late)
        sampler = tlp.Sampler(['/x/lane/Build'], proc=proc)
        sampler.prefixes = ['/x/lane/Build/']
        runner = tlp.Runner(self.args(), sampler, self.dir)
        killed = []
        original_kill = os.kill
        try:
            os.kill = lambda pid, sig: killed.append(pid)
            runner.run([sys.executable, '-c', 'print("hello")'])
        finally:
            os.kill = original_kill
        self.assertEqual(killed, [13])
        with open(os.path.join(self.dir, 'samples.jsonl')) as f:
            sampled = {pid for line in f for pid in json.loads(line)['hosts']}
        self.assertEqual(sampled, {13})

    def test_a_pid_that_stops_being_a_test_host_is_not_killed(self):
        # Seen as a test host, then (pid reused) the owner's build: the check
        # just before the signal must refuse it.
        proc = FakeProc({}, {13: (HOST, 1, (1.0, 5, 0, 1))})
        sampler = tlp.Sampler(['/x/lane/Build'], proc=proc)
        sampler.prefixes = ['/x/lane/Build/']
        runner = tlp.Runner(self.args(), sampler, self.dir)
        sampler.exclude_existing()
        runner.take_sample()
        runner.samples_file.close()
        runner.log_file.close()
        self.assertEqual(runner.seen_hosts, {13})
        proc.table[13] = (HOST, 1, (1.0, 5, 0, 1), OWNER_ARGS)
        killed = []
        original_kill = os.kill
        try:
            os.kill = lambda pid, sig: killed.append(pid)
            runner.kill_our_hosts()
        finally:
            os.kill = original_kill
        self.assertEqual(killed, [])


class WholeSuiteLockTests(unittest.TestCase):
    """run with no TEST and no COMMAND holds the whole-suite lock; with
    --no-wait it fails at once when another run holds it, before anything
    is started."""

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='tlp-lock-')
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.env = dict(os.environ)
        self.env['SWIFT_MIGRATION_SUITE_LOCK'] = os.path.join(self.dir, 'whole-suite.lock')
        self.env.pop('SWIFT_MIGRATION_SUITE_LOCK_HELD', None)

    def run_tool(self, *args):
        import subprocess
        tool = os.path.join(os.path.dirname(HERE), 'test_load_profile.py')
        return subprocess.run([sys.executable, '-B', tool] + list(args), env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, universal_newlines=True, timeout=60)

    def test_no_wait_fails_while_another_run_holds_it(self):
        import suite_guard
        lock = suite_guard.SuiteLock(self.env['SWIFT_MIGRATION_SUITE_LOCK'])
        self.assertTrue(lock.acquire('a sanitized suite elsewhere', ['xcodebuild'], wait=False))
        self.addCleanup(lock.release)
        out_dir = os.path.join(self.dir, 'out')
        p = self.run_tool('run', '--no-wait', '--out', out_dir)
        self.assertEqual(p.returncode, suite_guard.EXIT_LOCK_BUSY, p.stdout)
        self.assertIn('a sanitized suite elsewhere', p.stdout)
        # Nothing was started.
        self.assertFalse(os.path.exists(os.path.join(out_dir, 'output.log')))

    def test_a_maximum_below_the_allowance_is_a_usage_error(self):
        p = self.run_tool('run', '--test-allowance-seconds', '300', '--max-test-allowance-seconds', '60',
                          'ModernTests/A')
        self.assertEqual(p.returncode, 2, p.stdout)
        self.assertIn('--max-test-allowance-seconds is below --test-allowance-seconds', p.stdout)


class DefaultCommandTests(unittest.TestCase):
    """The default command gives XCTest a per-test time allowance
    (2026-11-24), unless it is 0."""

    def test_allowance_by_default(self):
        cmd = tlp.default_command(['ModernTests/A'])
        i = cmd.index('-test-timeouts-enabled')
        self.assertEqual(cmd[i:i + 6], ['-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance',
                                        '120', '-maximum-test-execution-time-allowance', '120'])

    def test_allowance_options_and_off(self):
        cmd = tlp.default_command([], allowance=120, maximum=300)
        self.assertIn('120', cmd)
        self.assertEqual(cmd[cmd.index('-maximum-test-execution-time-allowance') + 1], '300')
        self.assertNotIn('-test-timeouts-enabled', tlp.default_command([], allowance=0))

if __name__ == '__main__':
    unittest.main()
