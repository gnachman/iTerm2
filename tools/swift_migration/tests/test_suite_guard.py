"""Tests for tools/swift_migration/suite_guard.py: the stall watchdog, the
whole-suite lock and the bounded wait.

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_suite_guard.py

Nothing is built and no real test runs. The test command is a small Python
stand-in for xcodebuild (STUB below). A stand-in test host is a tiny C
program that waits for a signal, compiled once with `xcrun clang` and
copied to <tmp>/Build/Development/iTerm2.app/Contents/MacOS/iTerm2, so its
executable path and arguments are those of a real test host; the tests that
need it are skipped, visibly, without a compiler. The stand-in puts another
argument before `-suite iterm2-tests`, so that the cleanup patterns of other
scripts ("iTerm2 -suite iterm2-tests") never match it. Every lock is a file
in the test's temporary directory (SWIFT_MIGRATION_SUITE_LOCK), never the
machine's real one. Waits for an event poll with a generous bound; nothing
depends on how fast the machine is. Every process a test starts is killed
in its cleanup.
"""

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
TOOL = os.path.join(TOOLS, 'suite_guard.py')
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
sys.dont_write_bytecode = True

import suite_guard as sg  # noqa: E402

HOST_SOURCE = '#include <unistd.h>\nint main(void) { for (;;) pause(); }\n'
HOST_TAIL = os.path.join('iTerm2.app', 'Contents', 'MacOS', 'iTerm2')

# The stand-in for `xcodebuild test`: argv[1] is the behavior. With
# STUB_HOST it first starts that executable as a test host, in a session of
# its own as launchd's test hosts are outside xcodebuild's group, and writes
# its pid to $STUB_DIR/host.pid. It writes its own pid to stub.pid.
STUB = r'''
import os, subprocess, sys, time
d = os.environ['STUB_DIR']
mode = sys.argv[1]
host = os.environ.get('STUB_HOST')
if host:
    p = subprocess.Popen([host, '-NSTreatUnknownArgumentsAsOpen', 'NO', '-suite', 'iterm2-tests'],
                         start_new_session=True)
    open(os.path.join(d, 'host.pid'), 'w').write(str(p.pid))
open(os.path.join(d, 'stub.pid'), 'w').write(str(os.getpid()))
if host and os.environ.get('STUB_DECOY'):
    # Started during the run at the test host's very path, but with the
    # suite of a development build (`make run`), not -suite iterm2-tests.
    p = subprocess.Popen([host, '-NSTreatUnknownArgumentsAsOpen', 'NO', '-suite', 'iterm2-alt'],
                         start_new_session=True)
    open(os.path.join(d, 'decoy.pid'), 'w').write(str(p.pid))
def say(text):
    print(text, flush=True)
if mode == 'silent':
    say("Test Suite 'All tests' started at 2026-11-24 03:20:00.000.")
    say("Test Case '-[ModernTests.QuickTests testA]' started.")
    say("Test Case '-[ModernTests.QuickTests testA]' passed (0.001 seconds).")
    say("Test Case '-[ModernTests.HangTests testHang]' started.")
    time.sleep(600)
elif mode == 'parallel-silent':
    say("Test suite 'AlphaTests' started on 'My Mac - iTerm2 (1)'")
    say("Test case 'AlphaTests.testOne()' passed on 'My Mac - iTerm2 (1)' (0.003 seconds)")
    say("Test suite 'BetaTests' started on 'My Mac - iTerm2 (2)'")
    time.sleep(600)
elif mode == 'ticking':
    for i in range(12):
        say('tick %d' % i)
        time.sleep(0.4)
elif mode == 'serial-hang-logging':
    # A serial run: xcodebuild copies the host's output into its own, so a
    # hung test whose host keeps logging keeps the output coming.
    say("Test Case '-[ModernTests.HangTests testHang]' started.")
    for i in range(100):
        say('1795519455.629751 iTermSlowOperationGateway.m:634 fetchUserShell: gave up waiting (%d)' % i)
        time.sleep(0.3)
elif mode == 'slow-build':
    # Five seconds of build output before the first test: not a stall.
    for i in range(10):
        say('CompileC /tmp/x%d.o' % i)
        time.sleep(0.5)
    say("Test Case '-[ModernTests.QuickTests testA]' started.")
    say("Test Case '-[ModernTests.QuickTests testA]' passed (0.001 seconds).")
elif mode == 'late':
    time.sleep(3)
    say('late line')
elif mode == 'exit':
    say('exiting with %s' % sys.argv[2])
    sys.exit(int(sys.argv[2]))
elif mode in ('bundle-hang', 'bundle-dead-host', 'bundle-restart-hang'):
    # The layout of the night's result bundles (2026-11-24), under
    # $STUB_BUNDLE: two workers. Worker one enters a test and never
    # finishes it, then writes a log line anyway, as the night's hosts did;
    # its session log names the stand-in host's pid (bundle-hang) or a pid
    # that is no longer running (bundle-dead-host: a host that crashed and
    # was replaced). Worker two keeps finishing tests, and xcodebuild keeps
    # printing their results, so the log never goes quiet.
    root = os.path.join(os.environ['STUB_BUNDLE'], 'Staging', '1_Test', 'Diagnostics')
    config = os.path.join(root, 'ModernTests-16249F4B-1951-4DB3-80A7-1C2E532057BD-Configuration-'
                          'Test Scheme Action-Iteration-1')
    os.makedirs(os.path.join(root, 'My Mac_00006041-000870D90A07001C'))
    open(os.path.join(root, 'My Mac_00006041-000870D90A07001C', 'testmanagerd.log'), 'w').close()
    w1 = os.path.join(config, 'ModernTests-10E1727F-4035-4E66-A5B2-60B9EFAF2B4E')
    w2 = os.path.join(config, 'ModernTests-9E073E1B-5B96-4A82-A631-D2243B629090')
    os.makedirs(w1)
    os.makedirs(w2)
    dead = subprocess.Popen(['/usr/bin/true'])
    dead.wait()
    pid1 = int(open(os.path.join(d, 'host.pid')).read()) if mode == 'bundle-hang' else dead.pid
    restart = mode == 'bundle-restart-hang'
    with open(os.path.join(config, 'scheduling.log'), 'w') as f:
        f.write('2026-11-24 11:18:16 +0000: Parallelization enabled; test execution driven by the IDE\n')
    with open(os.path.join(w1, 'Session-ModernTests-2026-11-24_031812-HWfap5.log'), 'w') as f:
        f.write('03:18:13.114 xcodebuild[56396:74413660] Test process runnable PID is %d.\n' % pid1)
    with open(os.path.join(w2, 'Session-ModernTests-2026-11-24_031817-8rCELN.log'), 'w') as f:
        f.write('03:18:17.134 xcodebuild[56396:74413660] Test process runnable PID is %d.\n' % os.getpid())
    with open(os.path.join(w1, 'StandardOutputAndStandardError.txt'), 'w') as f:
        f.write("Test Suite 'KittyStalePlacementTests' started at 2026-11-24 03:23:10.000.\n")
        f.write("Test Case '-[ModernTests.KittyStalePlacementTests testDeleteByImageIdZeroKeepsOtherIdlessPlacements]' started.\n")
        f.write('1795519455.629751 iTermSlowOperationGateway.m:634 (-[iTermSlowOperationGateway '
                'fetchUserShellWithCompletion:]_block_invoke_4): fetchUserShell: gave up waiting for XPC reply\n')
    if restart:
        # As in a real run (2026-11-24): after the first host died, the
        # restarted host writes into the same directory and output file,
        # with a second Session log naming its pid, and hangs in a test.
        time.sleep(1.1)
        with open(os.path.join(w1, 'Session-ModernTests-2026-11-24_032001-Xy12Ab.log'), 'w') as f:
            f.write('03:20:01.000 xcodebuild[56396:74413660] Test process runnable PID is %d.\n'
                    % int(open(os.path.join(d, 'host.pid')).read()))
        with open(os.path.join(w1, 'StandardOutputAndStandardError.txt'), 'a') as f:
            f.write('Restarting after unexpected exit, crash, or test timeout; summary will include totals '
                    'from previous launches.\n')
            f.write("Test Suite 'SecondHostTests' started at 2026-11-24 03:20:02.000.\n")
            f.write("Test Case '-[ModernTests.SecondHostTests testHangsInTheSecondHost]' started.\n")
            f.write('a log line after the start\n')
    out2 = open(os.path.join(w2, 'StandardOutputAndStandardError.txt'), 'w')
    out2.write("Test Suite 'AlphaTests' started at 2026-11-24 03:23:10.000.\n")
    out2.flush()
    rounds = int(os.environ.get('STUB_ROUNDS', '100'))
    for i in range(rounds):
        out2.write("Test Case '-[ModernTests.AlphaTests test%d]' started.\n" % i)
        out2.write("Test Case '-[ModernTests.AlphaTests test%d]' passed (0.300 seconds).\n" % i)
        out2.flush()
        say("Test case 'AlphaTests.test%d()' passed on 'My Mac - iTerm2 (2)' (0.300 seconds)" % i)
        time.sleep(0.3)
'''

# A command run under the lock: writes <name>.started (with whether
# a.done existed then), waits until $STUB_DIR/release-<name> exists when
# HOLD is set, then writes <name>.done.
HOLDER = r'''
import os, sys, time
d = os.environ['STUB_DIR']
name = sys.argv[1]
open(os.path.join(d, name + '.pid'), 'w').write(str(os.getpid()))
open(os.path.join(d, name + '.started'), 'w').write(
    'a.done existed\n' if os.path.exists(os.path.join(d, 'a.done')) else 'a.done missing\n')
if os.environ.get('HOLD'):
    while not os.path.exists(os.path.join(d, 'release-' + name)):
        time.sleep(0.05)
open(os.path.join(d, name + '.done'), 'w').close()
'''


def wait_until(predicate, bound=60.0):
    end = time.monotonic() + bound
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def alive(pid):
    return sg.pid_alive(pid)


_COMPILED = {}


def compiled_host():
    """The path of the compiled stand-in host, or None without a compiler."""
    if 'path' not in _COMPILED:
        _COMPILED['path'] = None
        if shutil.which('xcrun'):
            d = tempfile.mkdtemp(prefix='suite_guard_host.')
            src = os.path.join(d, 'host.c')
            with open(src, 'w') as f:
                f.write(HOST_SOURCE)
            out = os.path.join(d, 'host')
            if subprocess.run(['xcrun', 'clang', '-o', out, src], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0:
                _COMPILED['path'] = out
                _COMPILED['dir'] = d
    return _COMPILED['path']


def tearDownModule():
    if _COMPILED.get('dir'):
        shutil.rmtree(_COMPILED['dir'], True)


class GuardBase(unittest.TestCase):
    def setUp(self):
        self.started_us = int(time.time() * 1000000)
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='suite_guard_test.'))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(self.kill_ours)
        self.ours = []
        self.stub = os.path.join(self.tmp, 'stub.py')
        with open(self.stub, 'w') as f:
            f.write(STUB)
        self.holder = os.path.join(self.tmp, 'holder.py')
        with open(self.holder, 'w') as f:
            f.write(HOLDER)
        self.lock = os.path.join(self.tmp, 'locks', 'whole-suite.lock')
        self.env = dict(os.environ)
        self.env.pop(sg.HELD_ENV, None)
        self.env['SWIFT_MIGRATION_SUITE_LOCK'] = self.lock
        self.env['STUB_DIR'] = self.tmp
        self.build = os.path.join(self.tmp, 'Build')

    def kill_ours(self):
        """Kills what a failing test left: only processes this test started
        (recorded pids, started after the test began)."""
        pids = list(self.ours)
        for name in ('host.pid', 'stub.pid', 'a.pid', 'b.pid', 'sleeper.pid', 'decoy.pid', 'child.pid'):
            try:
                with open(os.path.join(self.tmp, name)) as f:
                    pids.append(int(f.read()))
            except (OSError, ValueError):
                pass
        for pid in pids:
            info = sg.dr.proc_info(pid)
            if info is not None and info.start >= self.started_us:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def host_at(self, directory, *args):
        """Starts the stand-in host from directory/iTerm2.app/...; returns
        its Popen."""
        source = compiled_host()
        if source is None:
            self.skipTest('xcrun clang is not available to build the stand-in test host')
        path = os.path.join(directory, HOST_TAIL)
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            shutil.copy2(source, path)
        p = subprocess.Popen([path] + list(args), start_new_session=True)
        self.ours.append(p.pid)
        self.addCleanup(lambda: (p.kill(), p.wait()))
        return p

    def build_host(self):
        """The stand-in host's path under this test's build directory."""
        source = compiled_host()
        if source is None:
            self.skipTest('xcrun clang is not available to build the stand-in test host')
        path = os.path.join(self.build, 'Development', HOST_TAIL)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        shutil.copy2(source, path)
        return path

    def guard(self, args, env=None, timeout=180):
        out_path = os.path.join(self.tmp, 'guard.out')
        err_path = os.path.join(self.tmp, 'guard.err')
        with open(out_path, 'w') as out, open(err_path, 'w') as err:
            code = subprocess.run([sys.executable, '-B', TOOL] + args, stdout=out, stderr=err,
                                  env=env or self.env, timeout=timeout).returncode
        with open(out_path) as out, open(err_path) as err:
            return code, out.read(), err.read()

    def start_guard(self, args, name, env=None):
        err = open(os.path.join(self.tmp, name + '.err'), 'w')
        self.addCleanup(err.close)
        p = subprocess.Popen([sys.executable, '-B', TOOL] + args, stdout=subprocess.DEVNULL, stderr=err,
                             env=env or self.env)
        self.ours.append(p.pid)

        def stop():
            if p.poll() is None:
                p.kill()
                p.wait()
        self.addCleanup(stop)
        return p

    def read(self, name):
        with open(os.path.join(self.tmp, name)) as f:
            return f.read()

    def pid(self, name):
        return int(self.read(name))

    def stub_command(self, *mode):
        return [sys.executable, '-B', self.stub] + list(mode)


class StallTests(GuardBase):
    """A run that goes silent is diagnosed, killed and reported; a run that
    keeps printing is not; --stall-seconds 0 turns the watchdog off."""

    def run_stalled(self, mode, *extra, env_extra=None):
        env = dict(self.env)
        env['STUB_HOST'] = self.build_host()
        env.update(env_extra or {})
        log = os.path.join(self.tmp, 'test.log')
        stall_dir = os.path.join(self.tmp, 'stall')
        code, out, err = self.guard(['run', '--stall-seconds', '2', '--log', log, '--stall-dir', stall_dir,
                                     '--host-prefix', self.build] + list(extra) + ['--']
                                    + self.stub_command(mode), env=env)
        return code, out, err, stall_dir

    def test_a_silent_run_is_recorded_killed_and_reported(self):
        code, out, err, stall_dir = self.run_stalled('silent')
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        host = self.pid('host.pid')
        stub = self.pid('stub.pid')
        # Nothing is left running: the command's group and the test host.
        self.assertTrue(wait_until(lambda: not alive(host)), out)
        self.assertTrue(wait_until(lambda: not alive(stub)), out)
        # The records, written before the kill: the host was sampled while
        # it was alive.
        self.assertIn(str(host), self.read('stall/hosts.txt'))
        with open(os.path.join(stall_dir, 'sample-%d.txt' % host)) as f:
            self.assertIn('Call graph', f.read())
        processes = self.read('stall/processes.txt')
        self.assertIn('%CPU', processes)
        self.assertIn('threads', processes)
        self.assertIn('footprMB', processes)
        memory = self.read('stall/memory.txt')
        for what in ('memory_pressure', 'vm_stat', 'vm.swapusage'):
            self.assertIn(what, memory)
        self.assertIn('testHang', self.read('stall/log-tail.txt'))
        stall_text = self.read('stall/stall.txt')
        self.assertIn('STALLED', stall_text)
        self.assertIn('in progress (log): -[ModernTests.HangTests testHang]', stall_text)
        self.assertNotIn('testA]', stall_text.split('Tests in progress:')[1].split('Records')[0])
        self.assertIn('test host %d' % host, stall_text)
        # The account is on the console too, and the output went to both.
        self.assertIn('looks stalled (--stall-seconds 2): no test progress for 2 seconds', out)
        self.assertIn('STALLED', out)
        self.assertIn("Test Case '-[ModernTests.HangTests testHang]' started.", out)
        self.assertIn("Test Case '-[ModernTests.HangTests testHang]' started.", self.read('test.log'))

    def test_parallel_workers_name_their_open_classes(self):
        code, out, err, _ = self.run_stalled('parallel-silent')
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        text = self.read('stall/in-progress.txt')
        self.assertIn("worker My Mac - iTerm2 (1): class in progress (log): AlphaTests; last test finished: "
                      "AlphaTests.testOne() (passed)", text)
        self.assertIn('worker My Mac - iTerm2 (2): class in progress (log): BetaTests; last test finished: none',
                      text)

    def test_a_decoy_started_during_the_run_without_the_suite_is_left_alone(self):
        code, out, err, _ = self.run_stalled('silent', env_extra={'STUB_DECOY': '1'})
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        decoy = self.pid('decoy.pid')
        self.assertTrue(alive(decoy), 'the decoy %d was killed' % decoy)
        self.assertNotIn('%d ' % decoy, self.read('stall/hosts.txt'))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall', 'sample-%d.txt' % decoy)))
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))))

    def test_a_serial_host_that_keeps_logging_in_a_hung_test_is_a_stall(self):
        # No result bundle: once tests have begun, only test events are
        # progress, so log lines from a hung host do not keep it alive.
        code, out, err = self.guard(['run', '--stall-seconds', '2', '--log', os.path.join(self.tmp, 'test.log'),
                                     '--stall-dir', os.path.join(self.tmp, 'stall'), '--']
                                    + self.stub_command('serial-hang-logging'), timeout=120)
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        self.assertIn('no test event from xcodebuild', out)
        self.assertIn('in progress (log): -[ModernTests.HangTests testHang]', self.read('stall/stall.txt'))

    def test_build_output_before_the_tests_is_progress(self):
        code, out, err = self.guard(['run', '--stall-seconds', '2', '--'] + self.stub_command('slow-build'),
                                    timeout=120)
        self.assertEqual(code, 0, out + err)

    def test_a_signal_during_the_diagnosis_stops_it(self):
        env = dict(self.env)
        env['STUB_HOST'] = self.build_host()
        p = self.start_guard(['run', '--stall-seconds', '1', '--stall-dir', os.path.join(self.tmp, 'stall'),
                              '--host-prefix', self.build, '--'] + self.stub_command('silent'), 'diag', env=env)
        # hosts.txt is written before the samples, which take seconds.
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'stall', 'hosts.txt'))))
        p.terminate()
        self.assertEqual(p.wait(timeout=60), 128 + signal.SIGTERM)
        # Stopped part way: the diagnosis never finished.
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall', 'stall.txt')))
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))))
        self.assertTrue(wait_until(lambda: not alive(self.pid('stub.pid'))))

    def test_an_error_in_the_watch_still_kills_the_command(self):
        # The log is a directory, so opening it fails after the command
        # started.
        log = os.path.join(self.tmp, 'adir')
        os.makedirs(log)
        pgid = os.path.join(self.tmp, 'pgid')
        marker = os.path.join(self.tmp, 'survived')
        code, out, err = self.guard(['run', '--log', log, '--pgid-file', pgid, '--', '/bin/sh', '-c',
                                     'echo $$ > %s/stub.pid; /bin/sleep 3; touch %s' % (self.tmp, marker)],
                                    timeout=60)
        self.assertNotEqual(code, 0)
        self.assertIn('IsADirectoryError', err)
        # Killed at once: if it got as far as writing its pid, that process
        # is gone, and it never lives to write the marker three seconds on.
        if os.path.exists(os.path.join(self.tmp, 'stub.pid')):
            self.assertTrue(wait_until(lambda: not alive(self.pid('stub.pid'))), err)
        self.assertFalse(wait_until(lambda: os.path.exists(marker), bound=8.0))
        self.assertFalse(os.path.exists(pgid))

    def test_only_this_runs_hosts_are_sampled_or_killed(self):
        # Three processes that look like test hosts but are not this run's:
        # the same executable without -suite iterm2-tests (as `make run`
        # starts a development build), one with the suite outside the
        # build directory (another checkout or lane), and one at the very
        # path with the suite that existed before the run.
        self.build_host()
        own_suite = self.host_at(os.path.join(self.build, 'Development'), '-suite', 'iterm2-alt')
        elsewhere = self.host_at(os.path.join(self.tmp, 'OtherLane', 'Build'), '-x', '1', '-suite', 'iterm2-tests')
        before = self.host_at(os.path.join(self.build, 'Development'), '-x', '1', '-suite', 'iterm2-tests')
        code, out, err, _ = self.run_stalled('silent')
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        hosts = self.read('stall/hosts.txt')
        for p in (own_suite, elsewhere, before):
            self.assertIsNone(p.poll(), 'pid %d was killed\n%s' % (p.pid, out))
            self.assertNotIn('%d ' % p.pid, hosts)
            self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall', 'sample-%d.txt' % p.pid)))
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))))

    def test_output_that_keeps_coming_does_not_trigger_it(self):
        # Twelve lines 0.4 seconds apart: almost five seconds in all, more
        # than twice the two-second bound, but never two seconds of silence.
        log = os.path.join(self.tmp, 'test.log')
        code, out, err = self.guard(['run', '--stall-seconds', '2', '--log', log, '--']
                                    + self.stub_command('ticking'))
        self.assertEqual(code, 0, out + err)
        self.assertIn('tick 11', out)
        self.assertEqual(out, self.read('test.log'))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall')))

    def test_stall_seconds_zero_turns_it_off(self):
        code, out, err = self.guard(['run', '--stall-seconds', '0', '--log', os.path.join(self.tmp, 't.log'),
                                     '--'] + self.stub_command('late'))
        self.assertEqual(code, 0, out + err)
        self.assertIn('late line', out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall')))

    def test_the_commands_status_passes_through(self):
        code, out, _ = self.guard(['run', '--stall-seconds', '5', '--'] + self.stub_command('exit', '65'))
        self.assertEqual(code, 65, out)
        self.assertIn('exiting with 65', out)

    def test_hosts_left_after_a_normal_end_are_killed(self):
        env = dict(self.env)
        env['STUB_HOST'] = self.build_host()
        code, out, err = self.guard(['run', '--host-prefix', self.build, '--'] + self.stub_command('exit', '0'),
                                    env=env)
        self.assertEqual(code, 0, out + err)
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))), err)

    def test_sigterm_kills_the_command_and_the_hosts(self):
        env = dict(self.env)
        env['STUB_HOST'] = self.build_host()
        p = self.start_guard(['run', '--host-prefix', self.build, '--pgid-file', os.path.join(self.tmp, 'pgid'),
                              '--'] + self.stub_command('silent'), 'term', env=env)
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'host.pid'))
                                   and os.path.exists(os.path.join(self.tmp, 'stub.pid'))))
        # The command leads its own process group, whose id is in the file.
        self.assertEqual(self.pid('pgid'), self.pid('stub.pid'))
        p.terminate()
        self.assertEqual(p.wait(timeout=60), 128 + signal.SIGTERM)
        # The file goes with the step.
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'pgid')))
        self.assertTrue(wait_until(lambda: not alive(self.pid('stub.pid'))))
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))))

    def test_a_terminal_when_asked_and_its_carriage_returns_removed(self):
        log = os.path.join(self.tmp, 't.log')
        code, out, err = self.guard(['run', '--pty', '--log', log, '--', '/bin/sh', '-c',
                                     '[ -t 1 ] && echo on a terminal; printf "x\\r\\n"; printf "end"'],
                                    timeout=30)
        self.assertEqual(code, 0, err)
        with open(log, newline='') as f:
            text = f.read()
        self.assertEqual(text, 'on a terminal\nx\nend')

    def test_usage_errors(self):
        self.assertEqual(self.guard(['run'])[0], sg.EXIT_USAGE)
        self.assertEqual(self.guard(['run', '--no-wait', '--', 'true'])[0], sg.EXIT_USAGE)
        self.assertEqual(self.guard(['lock'])[0], sg.EXIT_USAGE)
        self.assertEqual(self.guard(['wait', '--pid', '1'])[0], sg.EXIT_USAGE)
        self.assertEqual(self.guard(['wait', '--pid', '0', '--seconds', '1'])[0], sg.EXIT_USAGE)
        self.assertEqual(self.guard([])[0], sg.EXIT_USAGE)


class BundleStallTests(GuardBase):
    """The result bundle as the progress signal: a host stuck in one test is
    found while another host and xcodebuild's log go on."""

    def run_bundle(self, mode, stall='3', rounds='100'):
        env = dict(self.env)
        env['STUB_HOST'] = self.build_host()
        env['STUB_BUNDLE'] = os.path.join(self.tmp, 'results', 'test.xcresult')
        env['STUB_ROUNDS'] = rounds
        return self.guard(['run', '--stall-seconds', stall, '--log', os.path.join(self.tmp, 'test.log'),
                           '--stall-dir', os.path.join(self.tmp, 'stall'), '--result-bundle', env['STUB_BUNDLE'],
                           '--host-prefix', self.build, '--'] + self.stub_command(mode), env=env)

    def test_a_host_stuck_in_one_test_is_found_while_the_others_go_on(self):
        code, out, err = self.run_bundle('bundle-hang')
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        host = self.pid('host.pid')
        self.assertIn('worker ModernTests-10E1727F-4035-4E66-A5B2-60B9EFAF2B4E has been inside one test', out)
        workers = self.read('stall/workers.txt')
        self.assertIn('worker ModernTests-10E1727F-4035-4E66-A5B2-60B9EFAF2B4E, host pid %d (running): '
                      'in progress for' % host, workers)
        self.assertIn("Test Case '-[ModernTests.KittyStalePlacementTests "
                      "testDeleteByImageIdZeroKeepsOtherIdlessPlacements]' started.", workers)
        self.assertIn('worker ModernTests-9E073E1B-5B96-4A82-A631-D2243B629090', workers)
        stall_text = self.read('stall/stall.txt')
        self.assertIn('testDeleteByImageIdZeroKeepsOtherIdlessPlacements', stall_text)
        hosts = self.read('stall/hosts.txt')
        self.assertRegex(hosts, r'(?m)^%d threads=[0-9]+ ' % host)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'stall', 'sample-%d.txt' % host)))
        self.assertIn('memory_pressure -Q', self.read('stall/memory.txt'))
        self.assertTrue(wait_until(lambda: not alive(host)))
        self.assertTrue(wait_until(lambda: not alive(self.pid('stub.pid'))))

    def test_a_host_restarted_in_the_same_directory_is_watched(self):
        # The first host of a worker died; its replacement writes into the
        # same directory and output file, adds a Session log, and hangs.
        code, out, err = self.run_bundle('bundle-restart-hang')
        self.assertEqual(code, sg.EXIT_STALLED, out + err)
        host = self.pid('host.pid')
        self.assertIn('worker ModernTests-10E1727F-4035-4E66-A5B2-60B9EFAF2B4E has been inside one test', out)
        workers = self.read('stall/workers.txt')
        self.assertIn('host pid %d (running)' % host, workers)
        self.assertIn('testHangsInTheSecondHost', workers)

    def test_a_dead_hosts_unfinished_test_is_not_a_stall(self):
        # A host that died in the last test its worker had is not replaced
        # (no test is left for it): its directory keeps the test started
        # and never finished while the other worker goes on. Forty rounds
        # of 0.3 seconds: twelve seconds, so the bundle is looked at twice
        # (every five seconds) with the dead host's test older than the
        # three-second bound.
        code, out, err = self.run_bundle('bundle-dead-host', rounds='40')
        self.assertEqual(code, 0, out + err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'stall')))


class HostsTests(unittest.TestCase):
    def test_a_pid_seen_earlier_is_checked_again_before_it_is_killed(self):
        # A host seen during the run may be gone and its pid reused by
        # another process by the time of the kill: that one is spared.
        d = tempfile.mkdtemp(prefix='suite_guard_hosts.')
        self.addCleanup(shutil.rmtree, d, True)
        other = subprocess.Popen(['/bin/sleep', '120'])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        hosts = sg.Hosts([d])
        hosts.seen.add(other.pid)
        self.assertEqual(hosts.kill(bound=1.0), [])
        self.assertIsNone(other.poll())


class WorkerTests(unittest.TestCase):
    """Worker.host_pid follows the newest host of a directory."""

    def test_second_host_hang_in_same_directory_is_stuck(self):
        # The reviewer's reproduction (2026-11-24, from a real run).
        d = tempfile.mkdtemp(prefix='suite_guard_worker.')
        self.addCleanup(shutil.rmtree, d, True)
        w_dir = os.path.join(d, 'ModernTests-UUID')
        os.makedirs(w_dir)
        out = os.path.join(w_dir, sg.OUTPUT_NAME)
        dead = subprocess.Popen(['/usr/bin/true'])
        dead.wait()
        with open(os.path.join(w_dir, 'Session-ModernTests-1.log'), 'w') as f:
            f.write('xcodebuild[1:2] Test process runnable PID is %d.\n' % dead.pid)
        with open(out, 'w') as f:
            f.write("Test Case '-[M.C testA]' started.\n")
        w = sg.Worker(w_dir, 0.0)
        w.poll(0.0)
        self.assertEqual(w.stuck_for(100.0), 0)  # its host is dead: not stuck
        live = subprocess.Popen(['/bin/sleep', '30'])
        self.addCleanup(lambda: (live.kill(), live.wait()))
        time.sleep(1.1)  # a later modification time for the second log
        with open(os.path.join(w_dir, 'Session-ModernTests-2.log'), 'w') as f:
            f.write('xcodebuild[1:2] Test process runnable PID is %d.\n' % live.pid)
        with open(out, 'a') as f:
            f.write("Restarting\nTest Case '-[M.C testB]' started.\nsome log line\n")
        w.poll(200.0)
        self.assertEqual(w.host_pid(), live.pid)
        self.assertGreaterEqual(w.stuck_for(1200.0), 900)


class LockTests(GuardBase):
    """The whole-suite lock: two runs serialize, --no-wait fails naming the
    holder, a dead holder's lock is recovered, and a run's own children do
    not wait for it."""

    def holder_command(self, name):
        return [sys.executable, '-B', self.holder, name]

    def start_holder(self, name='a', mode='lock'):
        env = dict(self.env)
        env['HOLD'] = '1'
        args = (['lock', '--label', 'holder %s' % name, '--'] if mode == 'lock'
                else ['run', '--lock', '--label', 'holder %s' % name, '--'])
        p = self.start_guard(args + self.holder_command(name), name, env=env)
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, name + '.started'))))
        return p

    def test_two_runs_serialize(self):
        a = self.start_holder('a')
        b = self.start_guard(['run', '--lock', '--label', 'second run',
                              '--lock-wait-file', os.path.join(self.tmp, 'b.waited'), '--']
                             + self.holder_command('b'), 'b')
        # B says whom it waits for, and its command does not start.
        self.assertTrue(wait_until(lambda: 'waiting for the whole-suite lock' in self.read('b.err')))
        waiting = self.read('b.err')
        self.assertIn('pid %d' % a.pid, waiting)
        self.assertIn('holder a', waiting)
        self.assertIn('(running)', waiting)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'b.started')))
        open(os.path.join(self.tmp, 'release-a'), 'w').close()
        self.assertEqual(a.wait(timeout=60), 0)
        self.assertEqual(b.wait(timeout=60), 0, self.read('b.err'))
        self.assertEqual(self.read('b.started'), 'a.done existed\n')
        self.assertRegex(self.read('b.waited'), r'^[0-9]+\n$')
        code, _, err = self.guard(['run', '--lock', '--lock-wait-file', os.path.join(self.tmp, 'c.waited'),
                                   '--', 'true'])
        self.assertEqual(code, 0, err)
        self.assertEqual(self.read('c.waited'), '0\n')
        self.assertIn('got the whole-suite lock after', self.read('b.err'))

    def test_no_wait_fails_and_names_the_holder(self):
        a = self.start_holder('a', mode='run')
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--'] + self.holder_command('b'))
        self.assertEqual(code, sg.EXIT_LOCK_BUSY, err)
        self.assertIn('pid %d' % a.pid, err)
        self.assertIn('holder a', err)
        self.assertIn(sg.ROOT, err)
        self.assertIn('--no-wait', err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'b.started')))
        code, out, _ = self.guard(['status'])
        self.assertEqual(code, 1)
        self.assertIn('holder a', out)
        open(os.path.join(self.tmp, 'release-a'), 'w').close()
        self.assertEqual(a.wait(timeout=60), 0)
        self.assertEqual(self.guard(['status'])[0], 0)

    def test_a_dead_holders_lock_is_recovered(self):
        a = self.start_holder('a')
        command = self.pid('a.pid')
        # The holder and everything it started die without releasing.
        os.killpg(command, signal.SIGKILL)
        a.kill()
        a.wait()
        self.assertTrue(wait_until(lambda: not alive(command)))
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--'] + self.holder_command('b'))
        self.assertEqual(code, 0, err)
        self.assertIn('recovered the whole-suite lock from pid %d' % a.pid, err)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'b.done')))

    def test_a_killed_holder_frees_the_lock_even_while_its_command_runs(self):
        # The command does not inherit the lock: an orphaned command that
        # hangs cannot hold every later suite off for ever.
        a = self.start_holder('a')
        a.kill()
        a.wait()
        self.assertTrue(alive(self.pid('a.pid')))
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--'] + self.holder_command('b'))
        self.assertEqual(code, 0, err)
        self.assertIn('recovered the whole-suite lock from pid %d' % a.pid, err)
        open(os.path.join(self.tmp, 'release-a'), 'w').close()
        self.assertTrue(wait_until(lambda: not alive(self.pid('a.pid'))))

    def test_released_at_the_end_even_if_a_descendant_keeps_it(self):
        # The command leaves a background process that inherited the lock's
        # descriptor; the explicit release at the end still frees the lock.
        code, out, err = self.guard(['lock', '--', '/bin/sh', '-c',
                                     '/bin/sleep 120 & echo $! > %s/sleeper.pid' % self.tmp])
        self.assertEqual(code, 0, err)
        self.assertTrue(alive(self.pid('sleeper.pid')))
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--'] + self.holder_command('b'))
        self.assertEqual(code, 0, err)

    def test_a_whole_suite_script_run_by_the_holder_does_not_wait_for_it(self):
        code, out, err = self.guard(['run', '--lock', '--', sys.executable, '-B', TOOL, 'run', '--lock',
                                     '--no-wait', '--'] + self.holder_command('b'))
        self.assertEqual(code, 0, out + err)
        # The inner run's messages reach the outer run's output.
        self.assertIn('already held for this run', out)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'b.done')))

    def test_the_nesting_variable_alone_does_not_pass_the_lock(self):
        # Inherited or stale: it names a live process that is not the
        # holder the lock file records, so the run must wait like any other.
        a = self.start_holder('a')
        env = dict(self.env)
        env[sg.HELD_ENV] = '%d:%s' % (os.getpid(), self.lock)
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--'] + self.holder_command('b'), env=env)
        self.assertEqual(code, sg.EXIT_LOCK_BUSY, err)
        self.assertIn('pid %d' % a.pid, err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'b.started')))
        open(os.path.join(self.tmp, 'release-a'), 'w').close()
        self.assertEqual(a.wait(timeout=60), 0)

    def test_the_lock_file_is_where_it_was_asked_for(self):
        self.assertFalse(os.path.exists(self.lock))
        self.assertEqual(self.guard(['lock', '--', 'true'])[0], 0)
        self.assertTrue(os.path.exists(self.lock))
        self.assertEqual(os.stat(os.path.dirname(self.lock)).st_mode & 0o777, 0o700)

    def test_the_default_lock_is_outside_every_checkout(self):
        self.assertEqual(sg.DEFAULT_LOCK, os.path.join(os.path.expanduser('~'), 'Library', 'Caches',
                                                       'com.googlecode.iterm2.swift-migration',
                                                       'whole-suite.lock'))


# A stand-in for tools/run_tests.expect, in its real shape: an expect
# script whose `spawn` puts its child in a session of its own, which starts
# a test host that ends up with parent pid 1 and a session of its own (as
# launchd's test hosts are), and which cleans up in a SIGINT/SIGTERM trap.
# The trap marks trap.ran, waits $TRAP_DELAY seconds (so the test can see
# the lock still held), kills its spawned child and exits 1; with
# $TRAP_STUBBORN it only marks trap.ran and carries on.
FAKE_RUN_TESTS = r"""#!/usr/bin/expect -f
set timeout -1
set d [lindex $argv 0]
set host [lindex $argv 1]
spawn /bin/sh -c "echo \$\$ > $d/child.pid; exec /bin/sleep 1000"
set spawned_pid [exp_pid]
exec python3 -c "import subprocess, sys; p = subprocess.Popen(\[sys.argv\[1\], '-x', '1', '-suite', 'iterm2-tests'\], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); open(sys.argv\[2\], 'w').write(str(p.pid))" $host $d/host.pid
if {[info exists env(TRAP_STUBBORN)]} {
    trap { exec touch $d/trap.ran } {SIGINT SIGTERM}
} else {
    trap { exec touch $d/trap.ran; after [expr {$env(TRAP_DELAY) * 1000}]; exec kill -9 $spawned_pid; exit 1 } {SIGINT SIGTERM}
}
exec touch $d/ready
expect eof
"""


class LockedRunTests(GuardBase):
    """suite_guard.py lock, as whole_suite.sh uses it around
    run_tests.expect: on a signal the command's own cleanup runs first,
    then what is left is killed (its process tree and this checkout's
    test hosts), and only then is the lock released."""

    def setUp(self):
        super().setUp()
        if not shutil.which('expect'):
            self.skipTest('expect is not installed')
        self.fake = os.path.join(self.tmp, 'run_tests.expect')
        with open(self.fake, 'w') as f:
            f.write(FAKE_RUN_TESTS)
        os.chmod(self.fake, 0o755)

    def start_locked(self, env_extra, *options):
        env = dict(self.env)
        env.update(env_extra)
        host = self.build_host()
        p = self.start_guard(['lock', '--host-prefix', self.build] + list(options)
                             + ['--', self.fake, self.tmp, host], 'locked', env=env)
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'ready'))
                                   or p.poll() is not None),
                        '%s %s %s' % (p.poll(), sorted(os.listdir(self.tmp)), self.read('locked.err')))
        self.ours.append(self.pid('child.pid'))
        return p

    def test_a_signal_lets_the_command_clean_up_then_kills_what_is_left(self):
        p = self.start_locked({'TRAP_DELAY': '5'})
        child, host = self.pid('child.pid'), self.pid('host.pid')
        self.assertTrue(alive(host))
        self.assertEqual(sg.dr.proc_info(host).ppid, 1)
        p.terminate()
        # run_tests.expect's own trap runs (it got SIGTERM, not SIGKILL),
        # and while it cleans up the lock is still held.
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'trap.ran'))))
        self.assertEqual(self.guard(['status'])[0], 1)
        self.assertEqual(p.wait(timeout=60), 128 + signal.SIGTERM)
        self.assertTrue(wait_until(lambda: not alive(child)))
        # The host, which no cleanup of the command reaches, is killed too.
        self.assertTrue(wait_until(lambda: not alive(host)))
        self.assertEqual(self.guard(['status'])[0], 0)
        self.assertIn('killed this checkout\'s test hosts: %d' % host, self.read('locked.err'))

    def test_a_command_that_ignores_the_signal_is_killed_after_the_grace(self):
        p = self.start_locked({'TRAP_STUBBORN': '1'}, '--term-grace', '2')
        child, host = self.pid('child.pid'), self.pid('host.pid')
        p.terminate()
        self.assertEqual(p.wait(timeout=60), 128 + signal.SIGTERM)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'trap.ran')))
        # Its spawned child is in a session of its own: killed as one of
        # the command's descendants, not by the group kill.
        self.assertTrue(wait_until(lambda: not alive(child)))
        self.assertTrue(wait_until(lambda: not alive(host)))
        self.assertEqual(self.guard(['status'])[0], 0)

    def test_a_signal_after_the_command_ended_still_lets_the_cleanup_finish(self):
        # The command starts a host, signals its parent and exits at once:
        # whenever the signal lands, the hosts are still killed, the status
        # is 128 + the signal, and the lock is free.
        host = self.build_host()
        code, out, err = self.guard(['lock', '--host-prefix', self.build, '--', sys.executable, '-c',
                                     'import os, signal, subprocess, sys\n'
                                     'p = subprocess.Popen([sys.argv[1], "-x", "1", "-suite", "iterm2-tests"],'
                                     ' start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n'
                                     'open(sys.argv[2], "w").write(str(p.pid))\n'
                                     'os.kill(os.getppid(), signal.SIGTERM)\n',
                                     host, os.path.join(self.tmp, 'host.pid')], timeout=60)
        self.assertEqual(code, 128 + signal.SIGTERM, err)
        self.assertNotIn('Traceback', err)
        self.assertTrue(wait_until(lambda: not alive(self.pid('host.pid'))), err)
        self.assertEqual(self.guard(['status'])[0], 0)

    def test_a_signal_as_soon_as_the_command_starts_is_caught(self):
        # Before the handlers were installed ahead of the command, a signal
        # in that window ended this program and orphaned the command.
        code, out, err = self.guard(['lock', '--term-grace', '2', '--', '/bin/sh', '-c',
                                     'echo $$ > %s/child.pid; kill -TERM $PPID; exec /bin/sleep 60' % self.tmp],
                                    timeout=60)
        self.assertEqual(code, 128 + signal.SIGTERM, err)
        self.assertTrue(wait_until(lambda: not alive(self.pid('child.pid'))), err)
        self.assertEqual(self.guard(['status'])[0], 0)

    def test_a_new_stall_report_makes_the_status_124(self):
        reports = os.path.join(self.tmp, 'reports')
        os.makedirs(reports)
        pattern = os.path.join(reports, 'test-stall-*.txt')
        # One that was there before does not count.
        open(os.path.join(reports, 'test-stall-old.txt'), 'w').close()
        code, out, err = self.guard(['lock', '--stall-reports', pattern, '--', '/bin/sh', '-c', 'exit 1'])
        self.assertEqual(code, 1, err)
        code, out, err = self.guard(['lock', '--stall-reports', pattern, '--', '/bin/sh', '-c',
                                     'echo stacks > %s/test-stall-new.txt; exit 1' % reports])
        self.assertEqual(code, sg.EXIT_STALLED, err)
        self.assertIn(os.path.join(reports, 'test-stall-new.txt'), err)
        # A report from a run that passed is not a stall.
        code, out, err = self.guard(['lock', '--stall-reports', pattern, '--', '/bin/sh', '-c',
                                     'echo stacks > %s/test-stall-ok.txt; exit 0' % reports])
        self.assertEqual(code, 0, err)

    def test_reports_written_while_waiting_for_the_lock_do_not_count(self):
        # The list of reports already there is taken once the lock is held.
        reports = os.path.join(self.tmp, 'reports')
        os.makedirs(reports)
        pattern = os.path.join(reports, 'test-stall-*.txt')
        lock = sg.SuiteLock(self.lock)
        self.assertTrue(lock.acquire('another run', ['x'], wait=False))
        p = self.start_guard(['lock', '--stall-reports', pattern, '--', '/bin/sh', '-c', 'exit 1'], 'waiter')
        self.assertTrue(wait_until(lambda: 'waiting for the whole-suite lock' in self.read('waiter.err')))
        open(os.path.join(reports, 'test-stall-other.txt'), 'w').close()
        lock.release()
        self.assertEqual(p.wait(timeout=60), 1, self.read('waiter.err'))


class HoldTests(GuardBase):
    """suite_guard.py hold: the lock held for a shell script's span."""

    def test_held_while_the_process_lives_and_children_pass(self):
        owner = subprocess.Popen(['/bin/sleep', '120'])
        self.ours.append(owner.pid)
        holder = subprocess.Popen([sys.executable, '-B', TOOL, 'hold', '--pid', str(owner.pid), '--label', 'per-class'],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=self.env,
                                  universal_newlines=True)
        self.ours.append(holder.pid)
        line = holder.stdout.readline().strip()
        self.assertRegex(line, r'^%s=[0-9]+:' % sg.HELD_ENV)
        self.assertEqual(self.guard(['status'])[0], 1)
        # A whole-suite step run with that in its environment does not wait.
        env = dict(self.env)
        env[sg.HELD_ENV] = line.split('=', 1)[1]
        code, out, err = self.guard(['run', '--lock', '--no-wait', '--', 'true'], env=env)
        self.assertEqual(code, 0, err)
        # Without it, another run is refused.
        self.assertEqual(self.guard(['run', '--lock', '--no-wait', '--', 'true'])[0], sg.EXIT_LOCK_BUSY)
        owner.kill()
        owner.wait()
        self.assertEqual(holder.wait(timeout=60), 0)
        self.assertEqual(self.guard(['status'])[0], 0)

    def test_a_nested_hold_passes_on_the_held_value(self):
        # A hold run under a process that already holds the lock prints the
        # value it inherited, so the steps under it find their ancestor's
        # lock (not a hold of its own that nobody holds).
        owner = subprocess.Popen(['/bin/sleep', '120'])
        self.ours.append(owner.pid)
        outer = subprocess.Popen([sys.executable, '-B', TOOL, 'hold', '--pid', str(owner.pid)],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=self.env,
                                 universal_newlines=True)
        self.ours.append(outer.pid)
        held = outer.stdout.readline().strip()
        env = dict(self.env)
        env[sg.HELD_ENV] = held.split('=', 1)[1]
        inner_owner = subprocess.Popen(['/bin/sleep', '120'])
        self.ours.append(inner_owner.pid)
        inner = subprocess.Popen([sys.executable, '-B', TOOL, 'hold', '--pid', str(inner_owner.pid), '--no-wait'],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env,
                                 universal_newlines=True)
        self.ours.append(inner.pid)
        self.assertEqual(inner.stdout.readline().strip(), held)
        env[sg.HELD_ENV] = held.split('=', 1)[1]
        self.assertEqual(self.guard(['lock', '--no-wait', '--', 'true'], env=env)[0], 0)
        for p in (inner_owner, owner):
            p.kill()
            p.wait()
        self.assertEqual(inner.wait(timeout=60), 0)
        self.assertEqual(outer.wait(timeout=60), 0)

    def test_hold_no_wait_when_held(self):
        lock = sg.SuiteLock(self.lock)
        self.assertTrue(lock.acquire('another run', ['x'], wait=False))
        self.addCleanup(lock.release)
        code, out, err = self.guard(['hold', '--pid', str(os.getpid()), '--no-wait'])
        self.assertEqual(code, sg.EXIT_LOCK_BUSY, err)
        self.assertIn('another run', err)


class WaitTests(GuardBase):
    def test_a_running_process_is_still_running_after_the_bound(self):
        sleeper = subprocess.Popen(['/bin/sleep', '120'])
        self.ours.append(sleeper.pid)
        began = time.monotonic()
        code, out, _ = self.guard(['wait', '--pid', str(sleeper.pid), '--seconds', '1'])
        self.assertEqual(code, sg.EXIT_STILL_RUNNING, out)
        self.assertGreaterEqual(time.monotonic() - began, 1.0)
        self.assertIn('still running after 1 seconds', out)
        sleeper.kill()
        sleeper.wait()

    def test_returns_when_the_process_ends(self):
        sleeper = subprocess.Popen(['/bin/sleep', '120'])
        self.ours.append(sleeper.pid)
        waiter = self.start_guard(['wait', '--pid', str(sleeper.pid), '--seconds', '120'], 'waiter')
        time.sleep(0.5)
        self.assertIsNone(waiter.poll())
        sleeper.kill()
        sleeper.wait()
        self.assertEqual(waiter.wait(timeout=60), 0)

    def test_a_process_that_is_gone_returns_at_once(self):
        p = subprocess.Popen(['/usr/bin/true'])
        p.wait()
        code, out, _ = self.guard(['wait', '--pid', str(p.pid), '--seconds', '60'], timeout=30)
        self.assertEqual(code, 0, out)
        self.assertIn('no process with pid %d is running' % p.pid, out)


class LogReadingTests(unittest.TestCase):
    def test_serial_tests_started_without_a_result(self):
        serial, parallel, ended = sg.in_progress_from_log([
            "Test Case '-[ModernTests.A testOne]' started.\n",
            "Test Case '-[ModernTests.A testOne]' passed (0.001 seconds).\n",
            "\x1b[1mTest Case '-[ModernTests.B testTwo]' started.\r\n",
        ])
        self.assertEqual(serial, ['-[ModernTests.B testTwo]'])
        self.assertEqual(parallel, [])
        self.assertFalse(ended)

    def test_parallel_workers(self):
        serial, parallel, ended = sg.in_progress_from_log([
            "Test suite 'A' started on 'W (1)'",
            "Test case 'A.testOne()' failed on 'W (1)' (0.010 seconds)",
            "Test suite 'A' failed on 'W (1)'",
            "Test suite 'C' started on 'W (1)'",
            "Test suite 'B' started on 'W (2)'",
            "Test case 'B.testX()' passed on 'W (2)' (1.000 seconds)",
            "Test suite 'B' passed on 'W (2)'",
            "** TEST EXECUTE FAILED **",
        ])
        self.assertEqual(serial, [])
        self.assertEqual(parallel, [('W (1)', 'C', 'A.testOne() (failed)'),
                                    ('W (2)', None, 'B.testX() (passed)')])
        self.assertTrue(ended)

    def test_test_from_a_sample(self):
        text = '\n'.join([
            'Call graph:',
            '    2345 Thread_100   DispatchQueue_1: com.apple.main-thread  (serial)',
            '    + 2345 start  (in dyld) + 1',
            '    +   2345 -[XCTestCase invokeTest]  (in XCTest) + 4',
            '    +     2345 -[HangTests testHang]  (in ModernTests) + 52  [0x1]',
            '    +       2345 usleep  (in libsystem_c.dylib) + 10',
            '    2345 Thread_101',
            '    + 2345 -[OtherTests testOther]  (in ModernTests) + 1',
        ])
        self.assertEqual(sg.test_from_sample(text), '-[HangTests testHang]')
        self.assertIsNone(sg.test_from_sample('Call graph:\n  1 Thread_1 DispatchQueue_1: com.apple.main-thread\n'))


if __name__ == '__main__':
    unittest.main()
