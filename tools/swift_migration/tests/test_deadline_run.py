"""Tests for tools/swift_migration/deadline_run.py, the nightly run's time limit.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_deadline_run.py'

The children are tiny shell scripts in a temporary directory. A test that
hits the deadline uses a child that would otherwise run for ten minutes, so
a slow machine can only make the deadline more certain, never less; the
tests do not depend on how fast anything runs. Waits for an event (a file
appearing, a process being gone) poll with a generous bound.

The sweep tests start grandchildren that leave the command's process group
and session (a new session, and a double fork whose parent exits), as Claude
Code's Bash tool and the migration's own tools do, and check that the sweep
after the command ends kills them and logs them, while a process the run did
not start is left alone.
"""

import datetime as dt
import os
import re
import uuid
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
TOOL = os.path.join(TOOL_DIR, 'deadline_run.py')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import deadline_run as dr  # noqa: E402

# The stand-in for Claude Code's input line (its docstring says what of
# Claude Code 2.1.331 it models: raw keys, C-c clears the line, an Enter in
# the same burst as long text is a paste and does not submit, /exit exits).
FAKE_CLAUDE = os.path.join(HERE, 'fake_claude_tui.py')

LA = ZoneInfo('America/Los_Angeles')


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def wait_until(predicate, bound=60.0):
    """Poll for an event with a generous bound. True if it happened."""
    end = time.monotonic() + bound
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


# Under Xcode's /usr/bin/python3 a daemon that the tool double-forks just
# before the command exits is out of the sweep's reach after a normal exit
# (deadline_run.py, "What is out of reach"); the python.org interpreter is
# the responsible process of what it starts, so there it is found.
APPLE_PYTHON = os.path.realpath(sys.executable).startswith(
    ('/usr/bin/', '/Applications/Xcode', '/Library/Developer/'))
ESCAPES_AFTER_NORMAL_EXIT = (('newsession',) if APPLE_PYTHON
                             else ('newsession', 'doublefork'))


def night(name):
    """A night id unique to this run, so that two test runs at once never
    take each other's processes for their own."""
    return '%s-%s' % (name, uuid.uuid4())


def gone(pid):
    # A killed orphan is reaped by launchd; until then kill(pid, 0) still
    # finds the zombie, so wait for the event.
    return wait_until(lambda: not alive(pid))


class SecondsUntilTest(unittest.TestCase):
    def test_later_today(self):
        now = dt.datetime(2026, 11, 19, 0, 0, tzinfo=LA)
        self.assertEqual(dr.seconds_until('07:00', now), 7 * 3600)

    def test_tomorrow_when_already_past(self):
        now = dt.datetime(2026, 11, 19, 8, 30, tzinfo=LA)
        self.assertEqual(dr.seconds_until('07:00', now), 22.5 * 3600)

    def test_exactly_now_is_tomorrow(self):
        now = dt.datetime(2026, 11, 19, 7, 0, tzinfo=LA)
        self.assertEqual(dr.seconds_until('07:00', now), 24 * 3600)

    def test_across_fall_back(self):
        # Sun 2026-11-01: 00:00 PDT to 07:00 PST is 8 real hours.
        now = dt.datetime(2026, 11, 1, 0, 0, tzinfo=LA)
        self.assertEqual(dr.seconds_until('07:00', now), 8 * 3600)

    def test_across_spring_forward(self):
        # Sun 2027-03-14: 00:00 PST to 07:00 PDT is 6 real hours.
        now = dt.datetime(2027, 3, 14, 0, 0, tzinfo=LA)
        self.assertEqual(dr.seconds_until('07:00', now), 6 * 3600)

    def test_fixed_offset_now_still_uses_the_zone(self):
        # datetime.now().astimezone() gives a fixed UTC offset, not a zone,
        # so the old code counted 7 hours from 00:00 PDT to "07:00" on the
        # fall-back day. With the zone given, it is 8 real hours.
        now = dt.datetime(2026, 11, 1, 0, 0, tzinfo=LA).astimezone(
            dt.timezone(dt.timedelta(hours=-7)))
        self.assertEqual(dr.seconds_until('07:00', now, LA), 8 * 3600)

    def test_fixed_offset_now_across_spring_forward(self):
        now = dt.datetime(2027, 3, 14, 0, 0, tzinfo=LA).astimezone(
            dt.timezone(dt.timedelta(hours=-8)))
        self.assertEqual(dr.seconds_until('07:00', now, LA), 6 * 3600)

    def test_bad_time(self):
        with self.assertRaises(ValueError):
            dr.seconds_until('25:00', dt.datetime(2026, 11, 19, tzinfo=LA))


class ShowDeadlineTest(unittest.TestCase):
    """--show-deadline prints the hard limit and the clean-stop time that
    nightly_start.sh puts in the orchestrator's prompt. "now" is injected."""

    def show(self, now, seconds='86400', until='07:00', *more):
        proc = subprocess.run([sys.executable, '-B', TOOL, '--show-deadline',
                               '--seconds', seconds, '--until', until,
                               '--now', now, '--tz', 'America/Los_Angeles']
                              + list(more),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True, timeout=120)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return dict(line.split('=', 1) for line in proc.stdout.splitlines())

    # With the default waits the stop sequence needs 10 + 300 + 60 + 10
    # seconds, plus 20 for the sweep's SIGKILL wait and slack: 400 seconds,
    # so it starts at 06:53:20 for a 07:00 hard limit. The clean stop is 45
    # minutes before the hard limit (the owner's 06:15).

    def test_fall_back_day(self):
        # 00:00 PDT to 07:00 PST is 8 real hours.
        got = self.show('2026-11-01T00:00')
        self.assertEqual(got['limit_seconds'], '28800')
        self.assertEqual(got['hard'], '2026-11-01 07:00:00 PST')
        self.assertEqual(got['stop_start'], '2026-11-01 06:53:20 PST')
        self.assertEqual(got['clean_stop'], '2026-11-01 06:15:00 PST')

    def test_spring_forward_day(self):
        got = self.show('2027-03-14T00:00')
        self.assertEqual(got['limit_seconds'], '21600')
        self.assertEqual(got['hard'], '2027-03-14 07:00:00 PDT')
        self.assertEqual(got['stop_start'], '2027-03-14 06:53:20 PDT')
        self.assertEqual(got['clean_stop'], '2027-03-14 06:15:00 PDT')

    def test_seconds_shorter_than_until(self):
        # Six hours from 00:00 PDT on the fall-back day is 05:00 PST.
        got = self.show('2026-11-01T00:00', seconds='21600')
        self.assertEqual(got['hard'], '2026-11-01 05:00:00 PST')
        self.assertEqual(got['clean_stop'], '2026-11-01 04:15:00 PST')

    def test_stop_sequence_length_follows_the_waits(self):
        got = self.show('2026-11-19T01:00', '86400', '07:00', '--interrupt-wait', '5',
                        '--grace', '100', '--term-grace', '15',
                        '--sweep-grace', '10')
        # 5 + 100 + 15 + 10 + 20 = 150 seconds before 07:00.
        self.assertEqual(got['stop_seconds'], '150')
        self.assertEqual(got['stop_start'], '2026-11-19 06:57:30 PST')
        self.assertEqual(got['clean_stop'], '2026-11-19 06:15:00 PST')


class WallClockDeadlineTest(unittest.TestCase):
    """The deadline follows the wall clock: time.monotonic() stops while
    the Mac sleeps, so a deadline counted on it alone would move later."""

    def test_remaining_time_follows_the_wall_clock(self):
        clock = {'wall': 1000.0}
        deadline = dr.Deadline(3600, wall=lambda: clock['wall'])
        self.assertEqual(deadline.remaining(), 3600)
        # The Mac slept for two hours: the monotonic clock did not move,
        # the wall clock did.
        clock['wall'] += 7200
        self.assertLessEqual(deadline.remaining(), 0)


def tmux_result(kind):
    """A tmux call's result as Tmux.run returns it, for each kind of
    outcome; the messages are tmux 3.8's own."""
    sock = '/tmp/x/s'
    table = {
        'alive': (0, '', True, None),
        'gone-session': (1, "can't find session: night\n", True, None),
        'gone-server': (1, 'no server running on %s\n' % sock, True, None),
        'gone-socket': (1, 'error connecting to %s (No such file or '
                        'directory)\n' % sock, True, None),
        'denied': (1, 'error connecting to %s (Permission denied)\n' % sock,
                   True, None),
        'error': (1, 'server exited unexpectedly\n', True, None),
        'timeout': (-1, '', False, 'timed out after 30 seconds'),
        'oserror': (-1, '', False, 'cannot run tmux: [Errno 35] Resource '
                    'temporarily unavailable'),
    }
    code, err, asked, error = table[kind]
    got = subprocess.CompletedProcess(['tmux'], code, '', err)
    got.asked = asked
    got.error = error
    return got


class ClassifyTest(unittest.TestCase):
    def test_classify(self):
        expected = {'alive': dr.ALIVE, 'gone-session': dr.GONE,
                    'gone-server': dr.GONE, 'gone-socket': dr.GONE,
                    'denied': dr.UNKNOWN, 'error': dr.UNKNOWN,
                    'timeout': dr.UNKNOWN, 'oserror': dr.UNKNOWN}
        for kind, state in expected.items():
            self.assertEqual(dr.Tmux.classify(tmux_result(kind)), state, kind)

    def test_a_gone_message_from_a_client_that_did_not_answer_is_unknown(self):
        got = tmux_result('gone-server')
        got.asked = False
        self.assertEqual(dr.Tmux.classify(got), dr.UNKNOWN)


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class FakeTmux:
    """Answers has-session from a script of tmux_result kinds."""
    name = 'night'

    def __init__(self):
        self.answers = []
        self.timeouts = []

    def session_state(self, timeout=None):
        self.timeouts.append(timeout)
        got = tmux_result(self.answers.pop(0))
        return dr.Tmux.classify(got), got


class EndWatchTest(unittest.TestCase):
    """The rule for "the session has ended", with a fake tmux, a fake clock
    and fake processes: no tmux, no sleeping."""

    PANE = "the pane's first process"

    def setUp(self):
        self.clock = FakeClock()
        self.tmux = FakeTmux()
        self.processes = None  # nothing tracked
        self.server = None     # the server's process not tracked
        self.tmp = tempfile.mkdtemp(prefix='endwatch_test.')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.status = os.path.join(self.tmp, 'status')
        # The watch's log lines are kept here instead of cluttering stderr.
        self.logged = []
        real_log = dr.log
        dr.log = self.logged.append
        self.addCleanup(setattr, dr, 'log', real_log)
        self.watch = dr.EndWatch(self.tmux, self.status, confirm=3, doubt=60,
                                 session_processes=lambda: self.processes,
                                 clock=self.clock,
                                 server_running=lambda: self.server)

    def at(self, when, kind):
        """The check at time `when`, with tmux answering `kind`."""
        self.clock.now = when
        self.tmux.answers.append(kind)
        return self.watch.check()

    def alive_pane(self, alive=True):
        self.processes = [(101, self.PANE, alive)]

    def alive_root(self, pane=True, root=True):
        self.processes = [(101, self.PANE, pane),
                          (102, dr.SESSION_ROOT, root)]

    def test_the_status_file_ends_it_at_once(self):
        open(self.status, 'w').close()
        self.clock.now = 0
        self.assertTrue(self.watch.check())
        self.assertEqual(self.tmux.answers, [])

    def test_present_is_not_over(self):
        for t in range(100):
            self.assertFalse(self.at(t, 'alive'))

    def test_gone_counts_after_three_answers_over_the_confirm_time(self):
        # Nothing tracked: tmux's confirmed answer decides.
        self.assertFalse(self.at(0, 'gone-session'))
        self.assertFalse(self.at(1, 'gone-session'))
        self.assertFalse(self.at(2, 'gone-session'))
        self.assertTrue(self.at(3, 'gone-session'))
        self.assertIn('answered 4 times', self.watch.over)
        self.assertIn("can't find session", self.watch.over)

    def test_three_quick_gone_answers_are_not_enough(self):
        self.assertFalse(self.at(0.0, 'gone-server'))
        self.assertFalse(self.at(0.2, 'gone-server'))
        self.assertFalse(self.at(0.4, 'gone-server'))
        self.assertFalse(self.at(2.9, 'gone-server'))
        self.assertTrue(self.at(3.0, 'gone-server'))

    def test_two_gone_answers_over_the_confirm_time_are_not_enough(self):
        self.assertFalse(self.at(0, 'gone-session'))
        self.assertFalse(self.at(5, 'gone-session'))
        self.assertTrue(self.at(6, 'gone-session'))

    def test_a_present_answer_starts_the_streak_again(self):
        self.assertFalse(self.at(0, 'gone-session'))
        self.assertFalse(self.at(1, 'gone-session'))
        self.assertFalse(self.at(2, 'alive'))
        self.assertFalse(self.at(3, 'gone-session'))
        self.assertFalse(self.at(4, 'gone-session'))
        self.assertFalse(self.at(5, 'gone-session'))
        self.assertTrue(self.at(6, 'gone-session'))

    def test_failures_neither_count_nor_end_it(self):
        for t, kind in enumerate(['error', 'timeout', 'oserror', 'denied'] * 5):
            self.assertFalse(self.at(t, kind))

    def test_gone_with_the_processes_dead_ends_it(self):
        self.alive_pane(False)
        for t in range(3):
            self.assertFalse(self.at(t, 'gone-session'))
        self.assertTrue(self.at(3, 'gone-session'))
        self.assertIn('gone too', self.watch.over)

    def test_gone_with_the_processes_alive_waits_for_the_doubt_time(self):
        self.alive_pane()
        for t in range(60):
            self.assertFalse(self.at(t, 'gone-session'), t)
        self.assertTrue(self.at(60, 'gone-session'))
        self.assertIn('still run', self.watch.over)

    def test_scattered_gone_answers_do_not_kill_live_processes(self):
        # Gone, two 30 second timeouts, gone, gone: three answers over 62
        # seconds, but with gaps longer than GONE_GAP the streak restarts.
        self.alive_pane()
        self.assertFalse(self.at(0, 'gone-session'))
        self.assertFalse(self.at(30, 'timeout'))
        self.assertFalse(self.at(60, 'timeout'))
        self.assertFalse(self.at(61, 'gone-session'))
        self.assertFalse(self.at(62, 'gone-session'))
        self.assertFalse(self.at(63, 'gone-session'))
        self.assertIsNone(self.watch.over)

    def test_gone_answers_fifteen_seconds_apart_are_not_a_streak(self):
        # Gaps between GONE_GAP and twice it: each answer starts a new
        # streak, so live processes are never killed on them.
        self.alive_pane()
        for t in range(0, 181, 15):
            self.assertFalse(self.at(t, 'gone-session'), t)
            self.assertFalse(self.at(t + 1, 'timeout'), t)

    def test_sustained_gone_answers_through_the_doubt_time_end_it(self):
        # Gone answers no more than GONE_GAP apart, failures between them.
        self.alive_pane()
        gap = dr.GONE_GAP
        t = 0.0
        while t < 60:
            self.assertFalse(self.at(t, 'gone-session'), t)
            self.assertFalse(self.at(t + gap / 2, 'timeout'), t)
            t += gap
        self.assertTrue(self.at(t, 'gone-session'))

    def test_no_server_while_the_server_process_lives_is_not_believed(self):
        # The socket file was deleted, or the connection was refused under
        # load: tmux says there is no server while its process runs.
        self.server = True
        for t in range(10):
            self.assertFalse(self.at(t, 'gone-server' if t % 2 else
                                     'gone-socket'))
        self.assertEqual(sum('not believed' in line for line in self.logged),
                         1, self.logged)
        self.server = False
        self.assertFalse(self.at(10, 'gone-server'))
        self.assertFalse(self.at(11, 'gone-server'))
        self.assertTrue(self.at(13, 'gone-server'))

    def test_cant_find_session_while_the_server_lives_is_believed(self):
        self.server = True
        for t in range(3):
            self.assertFalse(self.at(t, 'gone-session'))
        self.assertTrue(self.at(3, 'gone-session'))

    def test_no_present_answer_for_the_doubt_time_with_processes_dead(self):
        self.alive_pane(False)
        for t in range(60):
            self.assertFalse(self.at(t, 'timeout'), t)
        self.assertTrue(self.at(60, 'timeout'))
        self.assertIn('tracked processes are gone', self.watch.over)

    def test_no_present_answer_with_processes_alive_goes_on(self):
        self.alive_pane()
        for t in range(300):
            self.assertFalse(self.at(t, 'timeout'), t)

    def test_no_present_answer_with_nothing_tracked_goes_on(self):
        for t in range(300):
            self.assertFalse(self.at(t, 'error'), t)

    def test_scattered_gone_answers_with_processes_dead_end_after_doubt(self):
        # The streak never holds, but no present answer came for the doubt
        # time and the tracked processes are gone.
        self.alive_pane(False)
        t = 0
        while t < 60:
            self.assertFalse(self.at(t, 'gone-session' if t % 30 == 0
                                     else 'timeout'), t)
            t += 15
        self.assertTrue(self.at(60, 'timeout'))

    def test_a_long_healthy_run_never_reaches_the_fallback(self):
        # Present answers keep the fallback's clock at zero: one failure
        # after a long healthy run, with the processes gone, is no reason
        # to end, and nothing is logged about the fallback.
        for t in range(200):
            self.assertFalse(self.at(t, 'alive'), t)
        self.alive_pane(False)
        self.assertFalse(self.at(200, 'timeout'))
        self.assertFalse(self.at(201, 'error'))
        self.assertEqual([line for line in self.logged
                          if 'could not ask tmux' in line], [])

    def test_the_session_root_dead_without_a_status_ends_after_doubt(self):
        # claude died, the wrapper wrote no status, the pane lives on.
        self.alive_root(pane=True, root=False)
        for t in range(60):
            self.assertFalse(self.at(t, 'alive'), t)
        # Logged once, when it has lasted the confirm time.
        self.assertEqual(sum('has exited' in line for line in self.logged),
                         1, self.logged)
        self.assertTrue(self.at(60, 'alive'))
        self.assertIn('session root', self.watch.over)
        self.assertIn('no status', self.watch.over)

    def test_the_session_root_alive_is_not_over(self):
        self.alive_root()
        for t in range(120):
            self.assertFalse(self.at(t, 'alive'))

    def test_the_timeout_is_passed_to_tmux(self):
        self.tmux.answers.append('alive')
        self.watch.check(timeout=0.7)
        self.assertEqual(self.tmux.timeouts, [0.7])


class TrackedAliveTest(unittest.TestCase):
    def test_start_time_guards_against_pid_reuse(self):
        me = dr.proc_info(os.getpid())
        got = dr.tracked_alive([(os.getpid(), me.start, 'me'),
                                (os.getpid(), me.start + 1, 'reused'),
                                (99999999, 0, 'gone')])
        self.assertEqual(got, [(os.getpid(), 'me', True),
                               (os.getpid(), 'reused', False),
                               (99999999, 'gone', False)])

    def test_a_zombie_is_not_alive(self):
        # proc_info on macOS returns nothing for a real zombie (its BSD
        # info is gone), so the zombie check is for a kernel that reports
        # one; proc_info is replaced here to report it.
        real = dr.proc_info
        dr.proc_info = lambda pid: dr.ProcInfo(pid, 1, 0, dr.SZOMB, 5)
        self.addCleanup(setattr, dr, 'proc_info', real)
        self.assertEqual(dr.tracked_alive([(4242, 5, 'z')]),
                         [(4242, 'z', False)])


class ReadStatusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='read_status_test.')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.path = os.path.join(self.tmp, 'status')

    def test_missing_is_none_at_once(self):
        started = time.monotonic()
        self.assertIsNone(dr.read_status(self.path, settle=30))
        self.assertLess(time.monotonic() - started, 5)

    def test_a_number(self):
        with open(self.path, 'w') as fh:
            fh.write('3\n')
        self.assertEqual(dr.read_status(self.path), 3)

    def test_an_empty_file_is_read_again_until_written(self):
        # The file is written only after the reader has found it empty
        # (its first pause), so the first read always sees it empty.
        open(self.path, 'w').close()
        real_sleep = dr.time.sleep
        written = []

        def sleep(seconds):
            if not written:
                with open(self.path, 'w') as fh:
                    fh.write('7\n')
                written.append(True)
            real_sleep(seconds)
        dr.time.sleep = sleep
        try:
            self.assertEqual(dr.read_status(self.path, settle=30), 7)
        finally:
            dr.time.sleep = real_sleep
        self.assertTrue(written)

    def test_an_empty_file_that_stays_empty_is_none(self):
        open(self.path, 'w').close()
        self.assertIsNone(dr.read_status(self.path, settle=0.3))


class RunBase(unittest.TestCase):
    """Helpers shared by the process mode and the tmux mode tests."""

    def setUp(self):
        self.started_us = int(time.time() * 1000000)
        self.tmp = tempfile.mkdtemp(prefix='deadline_run_test.')
        # Cleanups run even when setUp or the test fails, last added first:
        # survivors are killed before the directory goes.
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(self.kill_survivors)

    def script(self, name, body):
        path = os.path.join(self.tmp, name)
        with open(path, 'w') as fh:
            fh.write('#!/bin/sh\n' + body)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return path

    def run_tool(self, args, timeout=120):
        # Output goes to files, not pipes: a grandchild that survives a
        # broken sweep would hold a pipe open and hang the test.
        out_path = os.path.join(self.tmp, 'tool.out')
        err_path = os.path.join(self.tmp, 'tool.err')
        with open(out_path, 'w') as out, open(err_path, 'w') as err:
            code = subprocess.run([sys.executable, '-B', TOOL] + args,
                                  stdout=out, stderr=err,
                                  timeout=timeout).returncode
        with open(out_path) as out, open(err_path) as err:
            return subprocess.CompletedProcess(args, code, out.read(),
                                               err.read())

    def kill_survivors(self):
        """Kill a grandchild that a broken sweep left, so a failing test
        leaves nothing running."""
        for name in ('newsession', 'doublefork', 'stubborn'):
            try:
                pid = self.read_pid(name)
            except (OSError, ValueError):
                continue
            # Only the process this test started: same program, started
            # after the test began (a reused pid fails both checks).
            info = dr.proc_info(pid)
            if (info is None or info.start < self.started_us
                    or 'sleep' not in dr.command_line(pid)
                    and 'python' not in dr.command_line(pid).lower()):
                continue
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def read_pid(self, name):
        with open(os.path.join(self.tmp, name)) as fh:
            return int(fh.read())

    TOOL_SCRIPT = r"""
import os, subprocess, sys, time
d = sys.argv[1]
# A child in a new session and process group.
p = subprocess.Popen(['/bin/sleep', '600'], start_new_session=True)
open(os.path.join(d, 'newsession'), 'w').write(str(p.pid))
# A daemon: fork, setsid, fork again, the middle process exits at once.
r, w = os.pipe()
if os.fork() == 0:
    os.setsid()
    pid = os.fork()
    if pid == 0:
        os.execv('/bin/sleep', ['/bin/sleep', '601'])
    os.write(w, str(pid).encode())
    os._exit(0)
os.close(w)
open(os.path.join(d, 'doublefork'), 'w').write(os.read(r, 32).decode())
open(os.path.join(d, 'ready'), 'w').close()
time.sleep(600)
"""

    def spawn_grandchildren_body(self):
        """Shell lines that start a long-lived tool in the background, as
        the migration's tools run, which starts two children outside the
        command's process group: one in a new session and one daemonized by
        a double fork. /bin/sleep is a platform binary, whose environment
        macOS does not show to other processes, and python3 is an app
        bundle, which macOS makes the responsible process of its children,
        so finding them needs the tracker's third rule."""
        tool = os.path.join(self.tmp, 'tool.py')
        with open(tool, 'w') as fh:
            fh.write(self.TOOL_SCRIPT)
        return ('%s %s %s &\n'
                'while [ ! -e %s/ready ]; do sleep 0.05; done\n'
                % (sys.executable, tool, self.tmp, self.tmp))

    def start_control(self):
        # A process the run did not start, without the marker.
        control = subprocess.Popen(['/bin/sleep', '600'])
        self.addCleanup(lambda: (control.kill(), control.wait()))
        return control


class RunTest(RunBase):
    def test_exit_status_passes_through(self):
        child = self.script('c', 'exit 3\n')
        proc = self.run_tool(['--seconds', '600', '--', child])
        self.assertEqual(proc.returncode, 3, proc.stderr)

    def test_success(self):
        out = os.path.join(self.tmp, 'out')
        child = self.script('c', 'echo "$@" > %s\n' % out)
        proc = self.run_tool(['--seconds', '600', '--', child, 'a b', 'c'])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out) as fh:
            self.assertEqual(fh.read(), 'a b c\n')

    def test_deadline_interrupts_then_reports_124(self):
        # The child records SIGINT and exits, as claude -p ends its turn.
        mark = os.path.join(self.tmp, 'got_int')
        child = self.script('c', "trap 'echo int > %s; exit 0' INT\n"
                            'echo $$ > %s/pid\n'
                            'while :; do sleep 1; done\n' % (mark, self.tmp))
        proc = self.run_tool(['--seconds', '1', '--grace', '600', '--',
                              child])
        self.assertEqual(proc.returncode, 124, proc.stderr)
        self.assertTrue(os.path.exists(mark))
        self.assertFalse(alive(self.read_pid('pid')))
        self.assertIn('deadline', proc.stderr)

    def test_child_that_ignores_interrupt_is_killed(self):
        child = self.script('c', "trap '' INT TERM\necho $$ > %s/pid\n"
                            'while :; do sleep 1; done\n' % self.tmp)
        proc = self.run_tool(['--seconds', '1', '--grace', '1',
                              '--term-grace', '1', '--', child])
        self.assertEqual(proc.returncode, 124, proc.stderr)
        self.assertFalse(alive(self.read_pid('pid')))

    def test_leftover_background_process_is_killed(self):
        # The child starts a grandchild in its process group and exits.
        child = self.script('c', 'sleep 600 &\necho $! > %s/pid\nexit 0\n'
                            % self.tmp)
        proc = self.run_tool(['--seconds', '600', '--', child])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        pid = self.read_pid('pid')
        # The grandchild was reparented to launchd, which reaps it after
        # the SIGKILL; until then it is a zombie that kill(pid, 0) still
        # finds. Poll for that event with a generous bound.
        gone = subprocess.run(
            ['/bin/sh', '-c', 'i=0; while kill -0 "$1" 2>/dev/null && '
             '[ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done; '
             '! kill -0 "$1" 2>/dev/null', 'sh', str(pid)], timeout=120)
        self.assertEqual(gone.returncode, 0)

    def test_sigterm_to_runner_is_forwarded(self):
        mark = os.path.join(self.tmp, 'got_term')
        ready = os.path.join(self.tmp, 'ready')
        child = self.script('c', "trap 'echo term > %s; exit 7' TERM\n"
                            'touch %s\n'
                            'while :; do sleep 1; done\n' % (mark, ready))
        runner = subprocess.Popen([sys.executable, '-B', TOOL, '--seconds',
                                   '600', '--', child],
                                  stderr=subprocess.PIPE,
                                  universal_newlines=True)
        try:
            # Wait for the child to be running, with a bound, by watching
            # for the file it creates. This is an event, not a timing guess.
            watcher = subprocess.run(
                ['/bin/sh', '-c', 'i=0; while [ ! -e "$1" ] && [ $i -lt 600 ];'
                 ' do sleep 0.1; i=$((i+1)); done; [ -e "$1" ]', 'sh', ready],
                timeout=120)
            self.assertEqual(watcher.returncode, 0)
            runner.terminate()
            _, err = runner.communicate(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
        self.assertEqual(runner.returncode, 7, err)
        self.assertTrue(os.path.exists(mark))

    # The sweep of everything the command started.

    def test_sweep_after_normal_exit(self):
        control = self.start_control()
        child = self.script('c', self.spawn_grandchildren_body() + 'exit 0\n')
        proc = self.run_tool(['--seconds', '600', '--night-id', night('test-night-1'),
                              '--sweep-grace', '5', '--', child])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for name in ESCAPES_AFTER_NORMAL_EXIT:
            pid = self.read_pid(name)
            self.assertTrue(gone(pid), '%s %d survived' % (name, pid))
            self.assertIn('killed pid %d ' % pid, proc.stderr)
            self.assertIn('/bin/sleep', proc.stderr)
        self.assertIsNone(control.poll())
        self.assertNotIn('killed pid %d ' % control.pid, proc.stderr)

    def test_sweep_after_deadline(self):
        control = self.start_control()
        child = self.script('c', self.spawn_grandchildren_body()
                            + "trap 'exit 0' INT\n"
                            'while :; do sleep 1; done\n')
        proc = self.run_tool(['--seconds', '1', '--grace', '600',
                              '--night-id', night('test-night-2'),
                              '--sweep-grace', '5', '--', child])
        self.assertEqual(proc.returncode, 124, proc.stderr)
        for name in ('newsession', 'doublefork'):
            pid = self.read_pid(name)
            self.assertTrue(gone(pid), '%s %d survived' % (name, pid))
            self.assertIn('killed pid %d ' % pid, proc.stderr)
        self.assertIsNone(control.poll())

    def test_sweep_kills_a_term_ignoring_process_with_sigkill(self):
        child = self.script('c', '%s -c "import os, signal, subprocess, sys; '
                            "p = subprocess.Popen([sys.executable, '-c', "
                            "'import signal, time; signal.signal(signal.SIGTERM,"
                            " signal.SIG_IGN); open(\\'%s/ready\\', \\'w\\')"
                            ".close(); time.sleep(600)'], start_new_session=True);"
                            " open(sys.argv[1], 'w').write(str(p.pid))\" "
                            '%s/stubborn\n'
                            'while [ ! -e %s/ready ]; do sleep 0.05; done\n'
                            'exit 0\n' % (sys.executable, self.tmp, self.tmp,
                                           self.tmp))
        proc = self.run_tool(['--seconds', '600', '--night-id', night('test-night-3'),
                              '--sweep-grace', '1', '--', child])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        pid = self.read_pid('stubborn')
        self.assertTrue(gone(pid))
        self.assertIn('killed pid %d (SIGKILL;' % pid, proc.stderr)

    def test_marker_in_environment_is_matched_exactly(self):
        # A process outside the run's tree, started during the run, whose
        # environment carries the exact NAME=value is the run's (for example
        # one that disclaimed responsibility); one whose value only starts
        # with the id is not, and neither is one started before the run.
        night = globals()['night']('test-night-4')
        code = 'import time; time.sleep(600)'
        before = subprocess.Popen(
            [sys.executable, '-c', code],
            env=dict(os.environ, SWIFT_MIGRATION_NIGHT_ID=night))
        self.addCleanup(lambda: (before.kill(), before.wait()))
        started = os.path.join(self.tmp, 'started')
        go = os.path.join(self.tmp, 'go')
        child = self.script('c', 'touch %s\n'
                            'while [ ! -e %s ]; do sleep 0.05; done\n'
                            'exit 0\n' % (started, go))
        runner = subprocess.Popen(
            [sys.executable, '-B', TOOL, '--seconds', '600', '--night-id',
             night, '--sweep-grace', '5', '--', child],
            stderr=subprocess.PIPE, universal_newlines=True)
        try:
            self.assertTrue(wait_until(lambda: os.path.exists(started)))
            marked = subprocess.Popen(
                [sys.executable, '-c', code],
                env=dict(os.environ, SWIFT_MIGRATION_NIGHT_ID=night))
            self.addCleanup(lambda: (marked.kill(), marked.wait()))
            near = subprocess.Popen(
                [sys.executable, '-c', code],
                env=dict(os.environ, SWIFT_MIGRATION_NIGHT_ID=night + 'x'))
            self.addCleanup(lambda: (near.kill(), near.wait()))
            visible = wait_until(
                lambda: (dr.environment_of(marked.pid) or [])
                .count('SWIFT_MIGRATION_NIGHT_ID=' + night) == 1, 10)
            open(go, 'w').close()
            _, err = runner.communicate(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
        if not visible:
            self.skipTest('%s hides its environment on this system'
                          % sys.executable)
        self.assertEqual(runner.returncode, 0, err)
        self.assertTrue(wait_until(lambda: marked.poll() is not None))
        self.assertIn('killed pid %d ' % marked.pid, err)
        self.assertIsNone(near.poll())
        self.assertIsNone(before.poll())

    def test_child_gets_the_marker(self):
        out = os.path.join(self.tmp, 'out')
        child = self.script('c', 'echo "$SWIFT_MIGRATION_NIGHT_ID" > %s\n'
                            % out)
        night_id = night('n-5')
        proc = self.run_tool(['--seconds', '600', '--night-id', night_id, '--',
                              child])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out) as fh:
            self.assertEqual(fh.read(), night_id + '\n')

    def test_until_option_is_accepted(self):
        child = self.script('c', 'exit 0\n')
        proc = self.run_tool(['--seconds', '600', '--until', '07:00', '--',
                              child])
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_missing_command(self):
        proc = self.run_tool(['--seconds', '5', '--',
                              os.path.join(self.tmp, 'nope')])
        self.assertEqual(proc.returncode, 127)

    def test_no_command(self):
        proc = self.run_tool(['--seconds', '5'])
        self.assertEqual(proc.returncode, 64)


TMUX = shutil.which('tmux') or next(
    (p for p in ('/opt/homebrew/bin/tmux', '/usr/local/bin/tmux')
     if os.access(p, os.X_OK)), None)


@unittest.skipUnless(TMUX, 'tmux is not installed; the tmux mode is untested')
class TmuxRunTest(RunBase):
    """The tmux mode: the session lives in a tmux server on a private socket
    in the test's temporary directory, and every test kills that server
    (and only that one) in teardown.

    The pane runs a small shell script standing in for the interactive
    claude. Keys sent with send-keys reach it on its terminal: it reads
    lines, and a line containing /exit makes it record that and exit, as
    Claude Code's /exit does. As the session wrapper written by
    nightly_start.sh does, it runs under `deadline_run.py --spawn-root`
    (tmux 3.8 makes every pane process its own responsible process, so the
    run needs a root of its own inside the pane), writes its exit status to
    a status file, and then waits to be closed."""

    NAME = 'night-test'

    def setUp(self):
        super().setUp()
        self.sock = os.path.join(self.tmp, 's')
        self.status = os.path.join(self.tmp, 'status')
        self.root_file = os.path.join(self.tmp, 'root')

    def tearDown(self):
        subprocess.run([TMUX, '-S', self.sock, 'kill-server'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # A pane program that a broken stop sequence left (it may ignore
        # every signal but SIGKILL): only this test's, by its path.
        try:
            pid = self.read_pid('pid')
        except (OSError, ValueError):
            pid = None
        if pid is not None:
            info = dr.proc_info(pid)
            if (info is not None and info.start >= self.started_us
                    and self.tmp in dr.command_line(pid)):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        super().tearDown()

    def pane_script(self, body):
        """A pane program: body, then its exit status into the status
        file, then it waits to be closed, as the session wrapper does."""
        inner = self.script('inner', body)
        return self.script('pane', '%s -B %s --spawn-root %s -- %s\n'
                           'rc=$?\necho $rc > %s\nexec sleep 600\n'
                           % (sys.executable, TOOL, self.root_file, inner,
                              self.status))

    # Shell lines that hand the pane to the stand-in for Claude Code's input
    # line, with %s for the test directory: /exit submitted ends it.
    EXIT_ON_SLASH_EXIT = 'exec %s -B %s %%s\n' % (sys.executable, FAKE_CLAUDE)

    def claude_with_banner(self, banner):
        """The stand-in, printing a dialog's text once its terminal is raw."""
        return 'exec %s -B %s %s "%s"\n' % (sys.executable, FAKE_CLAUDE, self.tmp, banner)

    def new_session(self, pane):
        return [TMUX, '-S', self.sock, '-f', '/dev/null', 'new-session', '-d',
                '-s', self.NAME, '-x', '120', '-y', '40', pane]

    def run_tmux(self, pane, *options, seconds='600', timeout=180):
        return self.run_tool(['--seconds', seconds, '--tmux-socket', self.sock,
                              '--tmux-session', self.NAME, '--tmux', TMUX,
                              '--status-file', self.status,
                              '--root-file', self.root_file,
                              '--interrupt-wait', '1', '--sweep-grace', '5']
                             + list(options) + ['--'] + self.new_session(pane),
                             timeout=timeout)

    def server_running(self):
        return subprocess.run([TMUX, '-S', self.sock, 'list-sessions'],
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0

    def test_tmux_exit_status_comes_from_the_status_file(self):
        proc = self.run_tmux(self.pane_script('exit 3\n'))
        self.assertEqual(proc.returncode, 3, proc.stderr)
        self.assertFalse(self.server_running())

    def test_tmux_success_and_marker(self):
        out = os.path.join(self.tmp, 'out')
        night_id = night('n-tmux')
        proc = self.run_tmux(self.pane_script(
            'echo "$SWIFT_MIGRATION_NIGHT_ID" > %s\n' % out),
            '--night-id', night_id)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out) as fh:
            self.assertEqual(fh.read(), night_id + '\n')

    def test_tmux_deadline_interrupts_then_types_exit(self):
        pane = self.pane_script(self.EXIT_ON_SLASH_EXIT % self.tmp)
        # The grace is shorter than the harness's 180 second bound, so a
        # pane that misses /exit is stopped by SIGTERM and fails the
        # got_exit assertion with the log, instead of hanging the test.
        # The stop sequence (1 + 60 + 60 + 5 + 20 = 146 seconds) starts
        # four seconds into the 150 second limit, after the stand-in has
        # its terminal in raw mode (keys before that are flushed).
        proc = self.run_tmux(pane, '--grace', '60', seconds='150')
        self.assertEqual(proc.returncode, 124, proc.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')),
                        proc.stderr)
        # Escape, then Ctrl-C (which clears the input line), then /exit and
        # Enter reached the pane in that order.
        with open(os.path.join(self.tmp, 'keys'), 'rb') as fh:
            keys = fh.read()
        self.assertLess(keys.index(b'\x1b'), keys.index(b'\x03'), keys)
        self.assertLess(keys.index(b'\x03'), keys.index(b'/exit'), keys)
        self.assertLess(keys.index(b'/exit'), keys.rindex(b'\r'), keys)
        self.assertIn('clearing the input line', proc.stderr)
        self.assertIn('deadline', proc.stderr)
        self.assertIn('Escape', proc.stderr)
        self.assertFalse(self.server_running())

    def test_tmux_session_that_ignores_everything_is_killed(self):
        pane = self.pane_script("trap '' INT TERM HUP\necho $$ > %s/pid\n"
                                'while :; do sleep 1; done < /dev/null\n'
                                % self.tmp)
        proc = self.run_tmux(pane, '--grace', '1', '--term-grace', '1',
                             seconds='1')
        self.assertEqual(proc.returncode, 124, proc.stderr)
        pid = self.read_pid('pid')
        self.assertTrue(gone(pid))
        self.assertFalse(self.server_running())
        # The processes the pane-group kill ended are itemized in the log.
        group_lines = [line for line in proc.stderr.splitlines()
                       if 'pane group' in line and ' %d ' % pid in line]
        self.assertTrue(group_lines, proc.stderr)

    def test_tmux_stop_sequence_ends_by_the_hard_limit(self):
        # A session that ignores everything needs the whole stop sequence
        # (1 + 3 + 2 seconds of waits, a 1 second sweep, 20 of slack: 27),
        # which therefore starts 27 seconds before the 40 second limit.
        pane = self.pane_script("trap '' INT TERM HUP\necho $$ > %s/pid\n"
                                'while :; do sleep 1; done < /dev/null\n'
                                % self.tmp)
        started = time.monotonic()
        proc = self.run_tool(['--seconds', '40', '--tmux-socket', self.sock,
                              '--tmux-session', self.NAME, '--tmux', TMUX,
                              '--status-file', self.status,
                              '--root-file', self.root_file,
                              '--interrupt-wait', '1', '--grace', '3',
                              '--term-grace', '2', '--sweep-grace', '1', '--']
                             + self.new_session(pane))
        elapsed = time.monotonic() - started
        self.assertEqual(proc.returncode, 124, proc.stderr)
        self.assertLessEqual(elapsed, 40, proc.stderr)
        self.assertIn('stop sequence starts', proc.stderr)
        self.assertTrue(gone(self.read_pid('pid')))

    def test_tmux_session_that_makes_no_progress_is_a_failed_start(self):
        # A startup dialog other than the trust dialog: it prints once and
        # waits; no transcript appears.
        pane = self.pane_script(self.claude_with_banner('Some other question? (y/n)'))
        # A short bound, so that a broken detector fails fast instead of
        # waiting for the 600 second limit.
        proc = self.run_tmux(pane, '--stall-seconds', '3', '--transcript',
                             os.path.join(self.tmp, 'transcript.jsonl'),
                             timeout=60)
        self.assertEqual(proc.returncode, 121, proc.stderr)
        self.assertIn('no progress', proc.stderr)
        self.assertFalse(self.server_running())

    def test_tmux_session_whose_output_changes_is_not_stalled(self):
        pane = self.pane_script('i=0; while [ $i -lt 12 ]; do echo tick $i; '
                                'i=$((i+1)); sleep 0.5; done\nexit 0\n')
        proc = self.run_tmux(pane, '--stall-seconds', '3', '--transcript',
                             os.path.join(self.tmp, 'transcript.jsonl'))
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_tmux_session_whose_transcript_grows_is_not_stalled(self):
        transcript = os.path.join(self.tmp, 'transcript.jsonl')
        pane = self.pane_script('echo working\ni=0; while [ $i -lt 12 ]; do '
                                'echo x >> %s; i=$((i+1)); sleep 0.5; done\n'
                                'exit 0\n' % transcript)
        proc = self.run_tmux(pane, '--stall-seconds', '3', '--transcript',
                             transcript)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_tmux_root_file_naming_a_process_outside_the_pane_is_ignored(self):
        # The root file is written by the session's own wrapper, so the
        # session can write it: a pid that is not in the pane must not make
        # the sweep kill what that process starts, even when it started
        # after the run did.
        go = os.path.join(self.tmp, 'go')
        ready = os.path.join(self.tmp, 'pane_ready')
        fake = os.path.join(self.tmp, 'fake_root')
        pane = self.script('pane', 'touch %s\n'
                           'while [ ! -s %s ]; do sleep 0.05; done\n'
                           'cp %s %s\ntouch %s\n'
                           'while [ ! -s %s/outsider_child ]; do sleep 0.05; done\n'
                           'sleep 2\necho 0 > %s\nexec sleep 600\n'
                           % (ready, fake, fake, self.root_file, go, self.tmp,
                              self.status))
        runner = subprocess.Popen(
            [sys.executable, '-B', TOOL, '--seconds', '600', '--tmux-socket',
             self.sock, '--tmux-session', self.NAME, '--tmux', TMUX,
             '--status-file', self.status, '--root-file', self.root_file,
             '--interrupt-wait', '1', '--sweep-grace', '5', '--']
            + self.new_session(pane),
            stderr=subprocess.PIPE, universal_newlines=True)
        outsider = None
        try:
            self.assertTrue(wait_until(lambda: os.path.exists(ready)))
            # Started after the run, outside the pane.
            outsider = subprocess.Popen(
                [sys.executable, '-c',
                 'import os, subprocess, sys, time\n'
                 'while not os.path.exists(sys.argv[1]): time.sleep(0.05)\n'
                 'p = subprocess.Popen(["/bin/sleep", "600"], start_new_session=True)\n'
                 'open(sys.argv[2], "w").write(str(p.pid))\n'
                 'time.sleep(600)\n', go,
                 os.path.join(self.tmp, 'outsider_child')])
            self.addCleanup(lambda: (outsider.kill(), outsider.wait()))
            self.assertTrue(wait_until(
                lambda: dr.proc_info(outsider.pid) is not None))
            info = dr.proc_info(outsider.pid)
            with open(fake + '.tmp', 'w') as fh:
                fh.write('%d %d\n' % (outsider.pid, info.start))
            os.rename(fake + '.tmp', fake)
            _, err = runner.communicate(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
        self.assertEqual(runner.returncode, 0, err)
        child = self.read_pid('outsider_child')
        self.addCleanup(lambda: alive(child) and os.kill(child, signal.SIGKILL))
        self.assertTrue(alive(child), err)
        self.assertNotIn('killed pid %d ' % child, err)
        self.assertIn('not in the pane', err)
        self.assertNotIn('session root in the pane: pid %d' % outsider.pid, err)

    def test_tmux_sweep_after_deadline_with_escaping_children(self):
        control = self.start_control()
        pane = self.pane_script(self.spawn_grandchildren_body()
                                + "trap '' TERM\n"
                                + self.EXIT_ON_SLASH_EXIT % self.tmp)
        proc = self.run_tmux(pane, '--night-id', night('test-night-tmux'),
                             '--grace', '600', seconds='2')
        self.assertEqual(proc.returncode, 124, proc.stderr)
        for name in ('newsession', 'doublefork'):
            pid = self.read_pid(name)
            self.assertTrue(gone(pid), '%s %d survived' % (name, pid))
            self.assertIn('killed pid %d ' % pid, proc.stderr)
        self.assertIsNone(control.poll())
        self.assertNotIn('killed pid %d ' % control.pid, proc.stderr)

    def test_tmux_sweep_after_normal_exit_with_escaping_children(self):
        control = self.start_control()
        pane = self.pane_script(self.spawn_grandchildren_body() + 'exit 0\n')
        proc = self.run_tmux(pane, '--night-id', night('test-night-tmux-2'))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for name in ESCAPES_AFTER_NORMAL_EXIT:
            pid = self.read_pid(name)
            self.assertTrue(gone(pid), '%s %d survived' % (name, pid))
        self.assertIsNone(control.poll())

    def test_spawn_root_passes_the_status_and_records_itself(self):
        child = self.script('c', 'exit 5\n')
        proc = self.run_tool(['--spawn-root', self.root_file, '--', child])
        self.assertEqual(proc.returncode, 5, proc.stderr)
        with open(self.root_file) as fh:
            pid, start = (int(x) for x in fh.read().split())
        self.assertGreater(pid, 0)
        self.assertGreater(start, 0)

    def test_tmux_child_of_a_root_that_exited_first_is_swept(self):
        # The root starts a platform binary in a new session (its
        # environment is hidden, so only responsibility links it), and
        # exits a few seconds later: by the end of the run macOS reports
        # the orphan as its own responsible process, so it is found only
        # because the run watched it while the root was alive.
        control = self.start_control()
        pane = self.pane_script(
            "/usr/bin/perl -e 'use POSIX; my $p = fork(); if ($p == 0) "
            '{ POSIX::setsid(); exec "/bin/sleep", "600"; } '
            'open(F, ">%s/newsession"); print F $p; close(F);\'\n'
            'sleep 4\nexit 0\n' % self.tmp)
        proc = self.run_tmux(pane)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        pid = self.read_pid('newsession')
        self.assertTrue(gone(pid), 'newsession %d survived\n%s'
                        % (pid, proc.stderr))
        self.assertIn('killed pid %d ' % pid, proc.stderr)
        self.assertIsNone(control.poll())

    def test_tmux_extra_window_does_not_keep_the_run_alive(self):
        # The session opens another window, which would keep the tmux
        # session alive after claude exits; the status file ends the run.
        pane = self.pane_script('%s new-window -d "sleep 600"\nexit 0\n'
                                % TMUX)
        proc = self.run_tmux(pane, timeout=120)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(self.server_running())

    def test_tmux_session_that_cannot_start(self):
        proc = self.run_tool(['--seconds', '600', '--tmux-socket', self.sock,
                              '--tmux-session', self.NAME, '--tmux', TMUX,
                              '--', TMUX, '-S', self.sock, 'no-such-command'])
        self.assertEqual(proc.returncode, 127, proc.stderr)

    def test_tmux_ended_from_outside_without_status(self):
        pane = self.script('pane', 'while :; do sleep 1; done\n')
        err_path = os.path.join(self.tmp, 'runner.err')
        with open(err_path, 'w') as err_file:
            runner = subprocess.Popen(
                [sys.executable, '-B', TOOL, '--seconds', '600',
                 '--tmux-socket', self.sock, '--tmux-session', self.NAME,
                 '--tmux', TMUX, '--status-file', self.status, '--']
                + self.new_session(pane),
                stdout=subprocess.DEVNULL, stderr=err_file)
        try:
            # Killed once the run has started (it knows the pane): a
            # session gone before that is a failed start (127).
            self.assertTrue(wait_until(
                lambda: re.search(r'pane pid \d+', self.read_log(err_path))
                or runner.poll() is not None))
            subprocess.run([TMUX, '-S', self.sock, 'kill-session', '-t',
                            self.NAME], check=True)
            runner.wait(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.wait()
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 125, err)
        # The log says what was observed, in tmux's own words, so that the
        # next occurrence can be diagnosed.
        self.assertIn('without an exit status', err)
        self.assertRegex(err, r"(can't find session|no server running"
                         r'|error connecting)')
        self.assertRegex(err, r'answered \d+ times')

    # A tmux client that cannot be run, times out, or fails some other way
    # says nothing about the session; only tmux's own answer that the
    # session or the server is gone does, and only when it repeats. The
    # first unattended night (2026-11-23) was ended at 01:55 by one failed
    # `tmux has-session` while the session sat healthy at its prompt.

    STUB_TMUX = r"""
d=%(dir)s
cmd=$3
mode=
if [ -s "$d/plan.$cmd" ]; then
  mode=$(head -n 1 "$d/plan.$cmd")
  tail -n +2 "$d/plan.$cmd" > "$d/plan.tmp.$$" && mv "$d/plan.tmp.$$" "$d/plan.$cmd"
elif [ -e "$d/broken.$cmd" ]; then
  mode=$(cat "$d/broken.$cmd")
elif [ -e "$d/broken.all" ]; then
  mode=$(cat "$d/broken.all")
fi
echo "$cmd ${mode:-ok} $*" >> "$d/calls"
case "$mode" in
  gone-server) echo "no server running on $2" >&2; exit 1 ;;
  gone-session) echo "can't find session: x" >&2; exit 1 ;;
  error) echo "server exited unexpectedly" >&2; exit 1 ;;
  hang) exec /bin/sleep 600 ;;
  slow) /bin/sleep 3 ;;
esac
exec %(tmux)s "$@"
"""

    def stub_tmux(self):
        """A tmux that passes every call to the real one, except as told by
        files in the test's directory: plan.<command> holds one behavior
        per line for the next calls of that command (ok, gone-server,
        gone-session, error, hang, slow: answer after 3 seconds),
        broken.<command> and broken.all one behavior for every call while
        they exist. Each call is recorded in calls as "<command> <behavior>
        <arguments>"."""
        return self.script('stubtmux', self.STUB_TMUX
                           % {'dir': self.tmp, 'tmux': TMUX})

    def calls(self, prefix):
        try:
            with open(os.path.join(self.tmp, 'calls')) as fh:
                return sum(1 for line in fh if line.startswith(prefix))
        except OSError:
            return 0

    def start_stubbed(self, pane, *options, seconds='600'):
        """The runner with the stub tmux, in the background; returns it and
        the path of its log. Waits until the start is over: the main loop
        has asked has-session (the start asks it once)."""
        err_path = os.path.join(self.tmp, 'runner.err')
        err = open(err_path, 'w')
        self.addCleanup(err.close)
        runner = subprocess.Popen(
            [sys.executable, '-B', TOOL, '--seconds', seconds,
             '--tmux-socket', self.sock, '--tmux-session', self.NAME,
             '--tmux', self.stub_tmux(), '--status-file', self.status,
             '--root-file', self.root_file, '--interrupt-wait', '1',
             '--sweep-grace', '2', '--tmux-confirm-seconds', '2',
             '--tmux-doubt-seconds', '30', '--tmux-timeout', '2']
            + list(options) + ['--'] + self.new_session(pane),
            stdout=subprocess.DEVNULL, stderr=err)

        def stop():
            if runner.poll() is None:
                runner.kill()
                runner.wait()
        self.addCleanup(stop)
        self.assertTrue(wait_until(lambda: self.calls('has-session') >= 2
                                   or runner.poll() is not None),
                        self.read_log(err_path))
        return runner, err_path

    def read_log(self, path):
        with open(path) as fh:
            return fh.read()

    def finish_and_wait(self, runner, err_path):
        open(os.path.join(self.tmp, 'finish'), 'w').close()
        runner.wait(timeout=120)
        return self.read_log(err_path)

    def waiting_pane(self):
        """A pane that runs until the test creates the file finish, then
        exits 0 with its status written."""
        return self.pane_script('while [ ! -e %s/finish ]; do sleep 0.1; done\n'
                                'exit 0\n' % self.tmp)

    def plan(self, command, *modes):
        with open(os.path.join(self.tmp, 'plan.' + command), 'w') as fh:
            fh.write(''.join(m + '\n' for m in modes))

    def test_tmux_one_failed_check_does_not_end_the_session(self):
        runner, err_path = self.start_stubbed(self.waiting_pane())
        before = self.calls('has-session')
        self.plan('has-session', 'error')
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= before + 3
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        # The failure is in the log with tmux's words and its exit status.
        self.assertIn('server exited unexpectedly', err)
        self.assertIn('has-session', err)

    def test_tmux_intermittent_failures_do_not_end_the_session(self):
        # Every kind of failure, and tmux claiming once or twice in a row
        # that the server or the session is gone (a refused connection
        # under load reads as "no server running").
        runner, err_path = self.start_stubbed(self.waiting_pane())
        before = self.calls('has-session')
        modes = ['gone-server', 'ok', 'error', 'gone-session', 'ok',
                 'gone-server', 'gone-server', 'ok', 'error', 'error',
                 'gone-session', 'gone-server', 'ok']
        self.plan('has-session', *modes)
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= before + len(modes) + 1
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)

    def test_tmux_a_call_that_times_out_does_not_end_the_session(self):
        runner, err_path = self.start_stubbed(self.waiting_pane())
        before = self.calls('has-session')
        self.plan('has-session', 'hang')
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= before + 3
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertIn('timed out', err)

    def test_tmux_that_cannot_be_run_for_seconds_does_not_end_the_session(self):
        # The tmux program cannot be started at all (OSError) for longer
        # than the confirmation time, as a fork that fails under load.
        runner, err_path = self.start_stubbed(self.waiting_pane())
        stub = os.path.join(self.tmp, 'stubtmux')
        os.rename(stub, stub + '.away')
        try:
            time.sleep(4)
        finally:
            os.rename(stub + '.away', stub)
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertIn('stubtmux', err)

    def test_tmux_claiming_gone_while_the_session_runs_does_not_end_it(self):
        # tmux says "can't find session" for longer than the confirmation
        # time, but the pane's processes are alive: not over until the
        # doubt time (30 seconds here) has passed. ("no server running"
        # while the server process lives is not believed at all; see
        # test_tmux_socket_file_deleted_under_a_healthy_server.)
        runner, err_path = self.start_stubbed(self.waiting_pane())
        broken = os.path.join(self.tmp, 'broken.has-session')
        with open(broken, 'w') as fh:
            fh.write('gone-session\n')
        try:
            time.sleep(5)
        finally:
            os.unlink(broken)
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertIn('still run', err)

    def test_tmux_failed_captures_are_not_a_stall(self):
        # A capture that fails is not an unchanged (empty) screen.
        with open(os.path.join(self.tmp, 'broken.capture-pane'), 'w') as fh:
            fh.write('error\n')
        runner, err_path = self.start_stubbed(
            self.waiting_pane(), '--stall-seconds', '2', '--transcript',
            os.path.join(self.tmp, 'transcript.jsonl'))
        # Six failed captures span five seconds, more than --stall-seconds;
        # a stall would start the stop sequence (send-keys Escape).
        self.assertTrue(wait_until(
            lambda: self.calls('capture-pane') >= 6
            or self.calls('send-keys') or runner.poll() is not None))
        self.assertEqual(self.calls('send-keys'), 0,
                         self.read_log(err_path))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertIn('capture-pane', err)

    def test_tmux_failures_are_logged_once_not_every_time(self):
        runner, err_path = self.start_stubbed(self.waiting_pane())
        before = self.calls('has-session')
        self.plan('has-session', *(['error'] * 8 + ['ok']))
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= before + 10
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertEqual(err.count('server exited unexpectedly'), 1, err)

    def test_tmux_broken_for_good_with_the_session_gone_ends(self):
        # tmux cannot be asked at all, and the pane's processes have
        # exited without writing a status: after the doubt time the
        # tracked processes decide, and the run ends as one that lost its
        # session (125), saying why.
        pane = self.script('pane', '%s -B %s --spawn-root %s -- %s\nexit 0\n'
                           % (sys.executable, TOOL, self.root_file,
                              self.script('inner', 'while [ ! -e %s/finish ]; '
                                          'do sleep 0.1; done\n' % self.tmp)))
        runner, err_path = self.start_stubbed(pane, '--tmux-doubt-seconds',
                                              '3')
        self.assertTrue(wait_until(lambda: os.path.exists(self.root_file)))
        with open(os.path.join(self.tmp, 'broken.all'), 'w') as fh:
            fh.write('error\n')
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 125, err)
        self.assertIn('could not ask tmux', err)

    def test_tmux_broken_for_good_with_the_session_alive_runs_to_the_deadline(self):
        # 32 seconds less the stop sequence (1 + 1 + 1 + 2 + 20 = 25): the
        # deadline is 7 seconds after the start, well after the doubt time.
        pane = self.pane_script('while :; do sleep 0.1; done\n')
        runner, err_path = self.start_stubbed(
            pane, '--tmux-doubt-seconds', '2', '--grace', '1',
            '--term-grace', '1', seconds='32')
        with open(os.path.join(self.tmp, 'broken.all'), 'w') as fh:
            fh.write('error\n')
        runner.wait(timeout=120)
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 124, err)
        self.assertIn('could not ask tmux', err)

    def test_tmux_that_hangs_at_the_deadline_does_not_delay_the_hard_limit(self):
        # Every tmux call hangs from just after the start, with the default
        # 30 second tmux timeout. The stop sequence (1 + 3 + 2 seconds of
        # waits, a 1 second sweep, 20 of slack: 27) starts 13 seconds in and
        # must be over by the 40 second hard limit: the SIGTERM and SIGKILL
        # of the pane need no tmux.
        pane = self.pane_script("trap '' INT TERM HUP\necho $$ > %s/pid\n"
                                'while :; do sleep 0.1; done < /dev/null\n'
                                % self.tmp)
        started = time.monotonic()
        runner, err_path = self.start_stubbed(
            pane, '--grace', '3', '--term-grace', '2', '--sweep-grace', '1',
            '--tmux-timeout', '30', seconds='40')
        with open(os.path.join(self.tmp, 'broken.all'), 'w') as fh:
            fh.write('hang\n')
        runner.wait(timeout=180)
        elapsed = time.monotonic() - started
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 124, err)
        self.assertLessEqual(elapsed, 40, err)
        self.assertTrue(gone(self.read_pid('pid')), err)

    def test_tmux_that_cannot_be_asked_at_the_start_is_not_a_failed_start(self):
        # The first eight has-session calls fail (more than the old start's
        # six tries), then tmux answers: the session runs and ends normally.
        self.plan('has-session', *(['error'] * 8))
        runner, err_path = self.start_stubbed(self.waiting_pane())
        # Twelve present answers after the failures: more than a few
        # seconds of the start, so the session must be past it.
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= 20
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)

    def test_tmux_signal_while_tmux_cannot_be_asked_at_the_start(self):
        # Every tmux call hangs from the start, so the pane pid is never
        # learned; a SIGTERM must still stop the run at once (after the
        # tmux call in progress), not when the stop sequence is due.
        with open(os.path.join(self.tmp, 'broken.all'), 'w') as fh:
            fh.write('hang\n')
        runner, err_path = self.start_stubbed(
            self.waiting_pane(), '--tmux-timeout', '3', '--grace', '2',
            '--term-grace', '1')
        signalled = time.monotonic()
        runner.terminate()
        runner.wait(timeout=120)
        elapsed = time.monotonic() - signalled
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 128 + signal.SIGTERM, err)
        # 3 for the call in progress, then 1 + 2 + 1 of waits, short tmux
        # calls and a 2 second sweep: far less than 40.
        self.assertLess(elapsed, 40, err)

    def test_tmux_session_gone_before_its_pane_is_known_is_a_failed_start(self):
        # The pane pid cannot be learned (display-message fails), and the
        # session ends after a second without writing a status: tmux's
        # confirmed answer that it is gone makes it a failed start.
        with open(os.path.join(self.tmp, 'broken.display-message'), 'w') as fh:
            fh.write('error\n')
        pane = self.script('pane', 'sleep 1\nexit 0\n')
        runner, err_path = self.start_stubbed(pane)
        runner.wait(timeout=120)
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 127, err)
        self.assertIn('could not be started', err)

    def test_tmux_slow_at_the_deadline_still_gets_exit_typed_once(self):
        # Every send-keys takes 3 seconds to answer. The stop sequence
        # (1 + 20 + 1 seconds of waits, a 2 second sweep, 20 of slack: 44)
        # starts 2 seconds into a 46 second limit; /exit and Enter come out
        # of the 20 second grace, so they are typed, once, and the pane
        # exits politely instead of being sent SIGTERM.
        with open(os.path.join(self.tmp, 'broken.send-keys'), 'w') as fh:
            fh.write('slow\n')
        pane = self.pane_script(self.EXIT_ON_SLASH_EXIT % self.tmp)
        runner, err_path = self.start_stubbed(
            pane, '--grace', '20', '--term-grace', '1', '--tmux-timeout',
            '30', seconds='46')
        runner.wait(timeout=120)
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 124, err)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')),
                        err)
        with open(os.path.join(self.tmp, 'calls')) as fh:
            typed = [line for line in fh
                     if line.startswith('send-keys') and '/exit' in line]
        self.assertEqual(len(typed), 1, typed)
        self.assertNotIn('still running; sending SIGTERM', err)

    def test_tmux_pane_pid_unknown_at_first_is_not_a_failed_start(self):
        # display-message keeps failing for a while although the session
        # is present: fourteen failures, more than the old start's six tries
        # each for the server pid and the pane pid; then the pane pid and
        # the server pid are answered.
        self.plan('display-message', *(['error'] * 14))
        runner, err_path = self.start_stubbed(self.waiting_pane())
        self.assertTrue(wait_until(
            lambda: self.calls('display-message') >= 16
            or runner.poll() is not None))
        self.assertTrue(wait_until(
            lambda: 'pane pid' in self.read_log(err_path)
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertNotIn('could not be started', err)

    def test_tmux_socket_file_deleted_under_a_healthy_server(self):
        # tmux then says "error connecting to ... (No such file or
        # directory)", but the server process it started is alive: not
        # believed, and with the pane's processes alive the session goes
        # on past the (short) doubt time.
        runner, err_path = self.start_stubbed(
            self.waiting_pane(), '--tmux-doubt-seconds', '3')
        os.unlink(self.sock)
        before = self.calls('has-session')
        self.assertTrue(wait_until(
            lambda: self.calls('has-session') >= before + 7
            or runner.poll() is not None))
        err = self.finish_and_wait(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertIn('server pid', err)
        self.assertIn('not believed', err)

    # The nudge (2026-11-24): a session idle at its prompt waiting for
    # background jobs got no turn at its clean stop. With --nudge-text the
    # supervisor types one line into it then. With the default 600 second
    # limit and a 596 second --clean-stop-margin, the clean stop is four
    # seconds after the start, long before the stop sequence (217 seconds).

    # Long, as the real one is: tmux types it in one burst, and Claude Code
    # takes long text with an Enter in the same burst for a paste.
    NUDGE = ('It is the clean stop time. Stop now as docs/swift-migration/workflow.md section 4 says: '
             'start nothing new, stop or abandon background jobs that have not finished, commit what '
             "passed, write the night's report, release lanes, then stop.")

    def recording_pane(self):
        """The stand-in for Claude Code's input line: each submitted line
        goes to the file lines; /exit ends it."""
        return self.pane_script(self.EXIT_ON_SLASH_EXIT % self.tmp)

    def type_exit(self, runner, err_path):
        """Ends the stand-in by typing /exit and Enter as two calls, as the
        owner would, through the real tmux (not the stub, so the calls
        file shows only the supervisor's own)."""
        # Keys typed before the stand-in has its terminal in raw mode are
        # flushed.
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'ready'))))
        subprocess.run([TMUX, '-S', self.sock, 'send-keys', '-t', self.NAME, '-l', '/exit'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.5)
        subprocess.run([TMUX, '-S', self.sock, 'send-keys', '-t', self.NAME, 'Enter'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        runner.wait(timeout=120)
        return self.read_log(err_path)

    def typed_lines(self):
        try:
            with open(os.path.join(self.tmp, 'lines')) as fh:
                return fh.read().splitlines()
        except OSError:
            return []

    def nudge_calls(self):
        try:
            with open(os.path.join(self.tmp, 'calls')) as fh:
                return [line for line in fh if line.startswith('send-keys') and self.NUDGE in line]
        except OSError:
            return []

    def test_tmux_nudge_is_typed_once_at_the_clean_stop(self):
        started = time.monotonic()
        runner, err_path = self.start_stubbed(self.recording_pane(), '--clean-stop-margin', '596',
                                              '--nudge-text', self.NUDGE)
        self.assertTrue(wait_until(lambda: self.NUDGE in self.typed_lines()
                                   or runner.poll() is not None), self.read_log(err_path))
        # Not before the clean stop: four seconds after the start ended.
        self.assertGreaterEqual(time.monotonic() - started, 3.5)
        self.assertTrue(wait_until(lambda: 'nudge typed' in self.read_log(err_path)))
        # Never again: ten more checks of the session go by.
        before = self.calls('has-session')
        self.assertTrue(wait_until(lambda: self.calls('has-session') >= before + 10
                                   or runner.poll() is not None))
        err = self.type_exit(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        # Submitted as one message: not left in the input as a paste.
        self.assertEqual(self.typed_lines(), [self.NUDGE])
        self.assertEqual(len(self.nudge_calls()), 1)
        # The text, then Enter as a call of its own a second later.
        with open(os.path.join(self.tmp, 'calls')) as fh:
            sends = [line.split(None, 2)[2] for line in fh if line.startswith('send-keys')]
        self.assertEqual(len(sends), 2, sends)
        self.assertIn(self.NUDGE, sends[0])
        self.assertNotIn('Enter', sends[0].replace(self.NUDGE, ''))
        self.assertTrue(sends[1].rstrip().endswith('Enter'), sends)
        self.assertIn('the nudge is typed into the session once, at the clean stop', err)
        self.assertIn(repr(self.NUDGE), err)
        self.assertIn('the clean stop: typing the nudge into the session', err)

    def test_tmux_no_nudge_without_the_option(self):
        runner, err_path = self.start_stubbed(self.recording_pane(), '--clean-stop-margin', '596')
        before = self.calls('has-session')
        # Well past the four seconds a nudge would have needed.
        self.assertTrue(wait_until(lambda: self.calls('has-session') >= before + 10
                                   or runner.poll() is not None))
        err = self.type_exit(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertEqual(self.calls('send-keys'), 0)
        self.assertNotIn('nudge', err)

    def test_tmux_nudge_that_tmux_fails_to_type_is_logged_not_retried(self):
        with open(os.path.join(self.tmp, 'broken.send-keys'), 'w') as fh:
            fh.write('error\n')
        runner, err_path = self.start_stubbed(self.recording_pane(), '--clean-stop-margin', '596',
                                              '--nudge-text', self.NUDGE)
        self.assertTrue(wait_until(lambda: 'could not be typed' in self.read_log(err_path)
                                   or runner.poll() is not None))
        before = self.calls('has-session')
        self.assertTrue(wait_until(lambda: self.calls('has-session') >= before + 10
                                   or runner.poll() is not None))
        err = self.type_exit(runner, err_path)
        # The session went on and ended by itself.
        self.assertEqual(runner.returncode, 0, err)
        self.assertEqual(len(self.nudge_calls()), 1)
        # Enter is still tried after a failed text call, once.
        self.assertEqual(self.calls('send-keys'), 2)
        self.assertIn('it is not retried', err)

    def test_tmux_nudge_into_a_hung_tmux_does_not_stop_the_supervisor(self):
        with open(os.path.join(self.tmp, 'broken.send-keys'), 'w') as fh:
            fh.write('hang\n')
        runner, err_path = self.start_stubbed(self.recording_pane(), '--clean-stop-margin', '596',
                                              '--nudge-text', self.NUDGE)
        self.assertTrue(wait_until(lambda: 'could not be typed' in self.read_log(err_path)
                                   or runner.poll() is not None))
        self.assertIn('timed out', self.read_log(err_path))
        before = self.calls('has-session')
        self.assertTrue(wait_until(lambda: self.calls('has-session') >= before + 5
                                   or runner.poll() is not None))
        err = self.type_exit(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertEqual(len(self.nudge_calls()), 1)

    def test_tmux_no_nudge_when_the_clean_stop_is_already_past(self):
        runner, err_path = self.start_stubbed(self.recording_pane(), '--clean-stop-margin', '700',
                                              '--nudge-text', self.NUDGE)
        self.assertTrue(wait_until(lambda: 'already past' in self.read_log(err_path)
                                   or runner.poll() is not None))
        err = self.type_exit(runner, err_path)
        self.assertEqual(runner.returncode, 0, err)
        self.assertEqual(self.calls('send-keys'), 0)

    def paste_into_the_input(self):
        """Types the nudge and Enter in one tmux call, which Claude Code
        takes for a paste: the text stays in the input, unsubmitted."""
        subprocess.run([TMUX, '-S', self.sock, 'send-keys', '-t', self.NAME, '-l', self.NUDGE, ';',
                        'send-keys', '-t', self.NAME, 'Enter'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # A 54 second limit with --grace 20 and --term-grace 1: the stop
    # sequence (1 + 20 + 1 + 2 + 20 = 44 seconds) starts 10 seconds in.
    SHORT_STOP = ('--grace', '20', '--term-grace', '1')

    def test_tmux_stop_sequence_exits_with_unsubmitted_text_in_the_input(self):
        # On 2026-11-24, against a real Claude Code, a nudge left in the
        # input made the old stop sequence submit "<nudge>/exit" as a
        # message instead of exiting.
        runner, err_path = self.start_stubbed(self.recording_pane(), *self.SHORT_STOP, seconds='54')
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'ready'))))
        self.paste_into_the_input()
        # The text is in the input, not submitted.
        self.assertTrue(wait_until(lambda: os.path.exists(os.path.join(self.tmp, 'keys'))))
        self.assertEqual(self.typed_lines(), [])
        runner.wait(timeout=120)
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 124, err)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')), err)
        self.assertFalse([line for line in self.typed_lines() if '/exit' in line], self.typed_lines())
        self.assertNotIn('still running; sending SIGTERM', err)

    def test_tmux_nudge_whose_enter_fails_is_cleared_by_the_stop_sequence(self):
        # The text is typed, the Enter after it fails: the text stays in the
        # input, and the stop sequence clears it before /exit. The clean
        # stop is four seconds in (54 - 50), the stop sequence at 10.
        self.plan('send-keys', 'ok', 'error')
        runner, err_path = self.start_stubbed(self.recording_pane(), *self.SHORT_STOP,
                                              '--clean-stop-margin', '50', '--nudge-text', self.NUDGE,
                                              seconds='54')
        runner.wait(timeout=120)
        err = self.read_log(err_path)
        self.assertEqual(runner.returncode, 124, err)
        self.assertIn('the Enter after the nudge could not be sent', err)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')), err)
        self.assertEqual(self.typed_lines(), [])

    def test_tmux_blocked_at_a_startup_dialog(self):
        pane = self.pane_script(self.claude_with_banner(
            'Quick safety check: Is this a project you created or one you trust?'))
        proc = self.run_tmux(pane, '--blocked-pattern', 'one you trust',
                             '--blocked-seconds', '120')
        self.assertEqual(proc.returncode, 122, proc.stderr)
        self.assertIn('one you trust', proc.stderr)
        self.assertFalse(self.server_running())

    def test_tmux_sigterm_to_runner_stops_the_session(self):
        ready = os.path.join(self.tmp, 'ready_pane')
        pane = self.pane_script('touch %s\n' % ready
                                + self.EXIT_ON_SLASH_EXIT % self.tmp)
        runner = subprocess.Popen(
            [sys.executable, '-B', TOOL, '--seconds', '600', '--tmux-socket',
             self.sock, '--tmux-session', self.NAME, '--tmux', TMUX,
             '--status-file', self.status, '--interrupt-wait', '1', '--']
            + self.new_session(pane),
            stderr=subprocess.PIPE, universal_newlines=True)
        try:
            self.assertTrue(wait_until(lambda: os.path.exists(ready)))
            runner.terminate()
            _, err = runner.communicate(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
        self.assertEqual(runner.returncode, 128 + signal.SIGTERM, err)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')))
        self.assertFalse(self.server_running())


if __name__ == '__main__':
    unittest.main()
