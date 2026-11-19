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

    EXIT_ON_SLASH_EXIT = (
        'while IFS= read -r line; do\n'
        '  case "$line" in *"/exit"*) echo exit > %s/got_exit; exit 0 ;; esac\n'
        'done\n')

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
        keys = os.path.join(self.tmp, 'keys')
        pane = self.pane_script(
            # Record the raw bytes of the first line, then behave like the
            # session: /exit ends it.
            'IFS= read -r first; printf %%s "$first" | od -c > %s\n'
            'case "$first" in *"/exit"*) echo exit > %s/got_exit; exit 0 ;; '
            'esac\n' % (keys, self.tmp) + self.EXIT_ON_SLASH_EXIT % self.tmp)
        proc = self.run_tmux(pane, '--grace', '600', seconds='1')
        self.assertEqual(proc.returncode, 124, proc.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'got_exit')),
                        proc.stderr)
        # Escape reached the pane before /exit.
        with open(keys) as fh:
            self.assertIn('033', fh.read())
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
        pane = self.pane_script('echo "Some other question? (y/n)"\n'
                                + self.EXIT_ON_SLASH_EXIT % self.tmp)
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
        runner = subprocess.Popen(
            [sys.executable, '-B', TOOL, '--seconds', '600', '--tmux-socket',
             self.sock, '--tmux-session', self.NAME, '--tmux', TMUX,
             '--status-file', self.status, '--'] + self.new_session(pane),
            stderr=subprocess.PIPE, universal_newlines=True)
        try:
            self.assertTrue(wait_until(self.server_running))
            subprocess.run([TMUX, '-S', self.sock, 'kill-session', '-t',
                            self.NAME], check=True)
            _, err = runner.communicate(timeout=120)
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.communicate()
        self.assertEqual(runner.returncode, 125, err)

    def test_tmux_blocked_at_a_startup_dialog(self):
        pane = self.pane_script(
            'echo "Quick safety check: Is this a project you created or '
            'one you trust?"\n' + self.EXIT_ON_SLASH_EXIT % self.tmp)
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
