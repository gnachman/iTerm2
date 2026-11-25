#!/usr/bin/env python3
"""The whole-suite lock and the stall watchdog of the migration's test scripts.

Part of the Objective-C to Swift migration tooling (docs/swift-migration/
orchestration.md section 3, "Heavy jobs and the machine"). macOS only.

Written after the second unattended night (2026-11-24), when five test
hosts in three sanitized whole suites each entered a test that waits with
no deadline for a dispatch or XPC callback that was never delivered (the
hangs began between 03:22 and 03:36). The cause, confirmed by observation
the same day with the screen locked: AppKit's window open and close
animations never finish while the screen is locked, each parks a
user-interactive dispatch thread, and at 80 the dispatch pool is exhausted,
so global-queue work and XPC replies stop in that host (bugs.md, "Dispatch
threads pile up in a long-running test host"); test hosts now launch with
-NSAutomaticWindowAnimationsEnabled NO. The allowances, the watchdog and
the lock remain needed for any other cause. That night nothing had a per-test timeout or a
stall watchdog, and the session waiting on the jobs had no bound and never
got a turn. The owner: "We need this process to be reliable." This tool
gives the suite scripts a run that stops making progress diagnosed, killed
and reported instead of waited for, and the orchestrator's rule of one
whole suite at a time on the machine (decided 2026-11-24 and recorded in
decisions.md; it bounds memory and keeps a failure attributable to one
run, and was not found to be the cause of the hangs).

Usage:
  suite_guard.py run [--stall-seconds N] [--log FILE] [--stall-dir DIR]
                     [--result-bundle PATH] [--host-prefix DIR]... [--pty]
                     [--pgid-file FILE] [--lock [--no-wait]
                     [--lock-wait-file FILE]] [--label TEXT]
                     -- COMMAND [ARG...]
  suite_guard.py lock [--no-wait] [--label TEXT] [--host-prefix DIR]...
                      [--term-grace S] [--stall-reports GLOB] -- COMMAND [ARG...]
  suite_guard.py hold --pid PID [--no-wait] [--label TEXT]
  suite_guard.py status
  suite_guard.py wait --pid PID --seconds N

run runs COMMAND (normally `xcodebuild test ...`) in its own session and
process group, with stdin from /dev/null and stdout and stderr together on
a pipe, or, with --pty, on a pseudo-terminal (on a terminal each line's
carriage returns are removed). The migration's scripts all use --pty:
through a pipe xcodebuild's output is block-buffered (on 2026-11-24 each
test.log stopped mid-line minutes before its tests hung, and a healthy
class ran 8.5 minutes while about 5 KB reached the log), and its results
and its end marker arrive on two streams out of order. On a terminal it
writes each line as it happens, as under tools/run_tests.expect and
test_load_profile.py. Everything COMMAND writes is copied to this
program's stdout and, with --log, to FILE, as `| tee FILE` did. The pid of
COMMAND's process group is written to --pgid-file when given, so that a
script interrupted while this runs can kill the group itself; the file is
removed when run ends. With --lock-wait-file, the seconds spent waiting for
the lock (0 when it was free) are written there once it is held, so that a
caller can leave the wait out of its own timing (fast_tests.sh's budget).

The stall watchdog (run, --stall-seconds N; 0 turns it off, which is the
default here; each script sets its own default, above the per-test time
allowance it gives XCTest, so that XCTest's own timeout acts first and
this is the backstop). Its progress signal, with --result-bundle PATH (the
command's -resultBundlePath), is the test hosts' own output in the bundle
xcodebuild is writing, looked at every 5 seconds:
  PATH/Staging/1_Test/Diagnostics/<configuration>/ModernTests-<uuid>/
      StandardOutputAndStandardError.txt   all one host writes, the XCTest
                                           lines among it, as it happens
      Session-ModernTests-<time>-<id>.log  xcodebuild's session log, with
                                           "Test process runnable PID is N"
  PATH/Staging/1_Test/Diagnostics/<configuration>/scheduling.log
                                           which classes went to which host
(one ModernTests-<uuid> directory per worker, in a serial run too; read from
the night's own bundles, 2026-11-24, and a serial run's). When XCTest
restarts a worker's host (after a crash or a test timeout) the new host
writes into the same directory and the same output file and adds a Session
log of its own (seen in a real run on 2026-11-24): the worker's host is the
last pid of its newest Session log, read again whenever the Session logs
change. A test event is a "Test Case '...' started." line, a test case's
result line, or a "Test Suite '...' started|passed|failed at" line, in a
host's output or in xcodebuild's own (where a parallel run's results read
"Test case '...' passed on '...'" and "Test suite '...' started on"). The
run is stalled when a worker's last test event is a start (a test, or a
class's setup) and it has had no other test event for N seconds while its
host is alive, which names the test and its host even while other hosts go
on; or when for N seconds there has been no progress anywhere: until the
first test event, progress is any output from xcodebuild; from then on,
only a test event in xcodebuild's output or a host's (in a serial run
xcodebuild copies the host's log lines into its own output, so a hung host
that keeps logging would otherwise look alive). A worker whose host died in
its last test and was not replaced (no test was left for it) is not stuck.
A host's file going quiet is not the signal either: on the night, hosts
went on writing log lines (an XPC give-up, for example) after their hung
test's start line. When the run stalls, before anything is
killed, this is recorded under --stall-dir (default: stall/ beside --log):
  workers.txt        each host of the bundle: its pid and whether it runs,
                     the test in progress and for how long, or its last
                     test event, and its output file's size and time
  hosts.txt          the test hosts of this run (below), one per line, with
                     their thread count (`ps -M -p PID`)
  sample-<pid>.txt   for each of them (at most 8), `sample <pid> 3 -mayDie`:
                     every thread's stack
  processes.txt      every process (ps: pid, ppid, pgid, user, state, %cpu,
                     %mem, rss, elapsed time, command), then this user's
                     processes with their thread count and memory footprint
                     (phys_footprint, read with libproc), largest first
  memory.txt         `memory_pressure -Q`, `vm_stat`, `sysctl vm.swapusage
                     kern.memorystatus_vm_pressure_level`
  log-tail.txt       the last 300 lines of --log
  in-progress.txt    the tests in progress (below)
  stall.txt          what happened, the tests in progress, and these files
Every command is bounded (sample 30 seconds, the others 20; a command that
overruns is killed and the file says so), and so is the whole diagnosis, so
a hung tool cannot hang the watchdog; a signal (INT, TERM, HUP) during the
diagnosis stops it within about a quarter of a second, and run then kills
and exits as for any signal. Then COMMAND's process group is
killed with SIGKILL, then this run's test hosts, and run exits with status
124 (EXIT_STALLED), whatever COMMAND's status would have been, so a caller
can tell a stall from a test failure.

The tests in progress: from the result bundle, each host's (workers.txt);
from the log: in a serial run, each test with a
"Test Case '...' started." line and no result line; in a parallel run, for
each worker (the name after "on" in "Test suite 'X' started on 'W'"), the
class it started last without a result for it, with the last test it
finished; and from each test host's sample, the innermost ModernTests frame
on its main thread, as tools/report_test_stall.sh reads it.

The test hosts of this run, the only processes sampled or signalled besides
COMMAND's group: a process whose executable path is under one of the
--host-prefix directories (each script gives its own build directory, for
example tmp/sanitizers/thread/Build/) and ends in
iTerm2.app/Contents/MacOS/iTerm2, whose arguments contain
`-suite iterm2-tests` (the identification of tools/run_tests.expect, which
kills by "<checkout>/Build/.*/iTerm2.app/Contents/MacOS/iTerm2 -suite
iterm2-tests", and of test_load_profile.py, whose functions this uses), and
which did not exist when COMMAND started. Each is checked again just before
it is signalled. The owner's own iTerm2 runs from /Applications with his
own suite, and a development build from `make run` with `-suite <checkout
name>`: neither is ever a test host. Without --host-prefix no test host is
sampled or killed. After COMMAND ends, by itself or not, this run's test
hosts are killed as well (the scripts' own kill_test_hosts still runs too).

The whole-suite lock (run --lock, and lock): at most one whole-suite run
(plain or sanitized) at a time across every checkout and lane of this user,
by day and by night (orchestration.md section 3). It is an flock(2) on a
file at a fixed per-user path outside every checkout,
  ~/Library/Caches/com.googlecode.iterm2.swift-migration/whole-suite.lock
(SWIFT_MIGRATION_SUITE_LOCK names another file; the tests use it). The file
holds the holder's pid, checkout, label, command and start time. By
default a run waits for the lock, saying first who holds it; with --no-wait
it fails at once with status 75 (EXIT_LOCK_BUSY), naming the holder. A
holder that dies leaves no lock behind: the kernel releases an flock when
the last descriptor of it closes, so a dead holder's lock is recovered by
the next run, which says whose it was. Only this program holds the lock:
COMMAND does not inherit its descriptor. So if this program is killed with
SIGKILL (which nothing it can do survives) while COMMAND runs on, the lock
is free at once and the next whole suite may overlap the orphaned one for
as long as it runs; with an inherited lock, an orphaned COMMAND that hangs
(the case this tool exists for, now without its watchdog) would hold every
later suite off for ever. A bounded overlap is the better trade. The
suite scripts kill COMMAND's group themselves when they are interrupted
(--pgid-file), and SIGINT, SIGTERM and SIGHUP to this program kill it too.
A command run under the lock gets SWIFT_MIGRATION_SUITE_LOCK_HELD in its
environment, so that a whole-suite script it runs (whole_suite.sh run as
`suite_guard.py lock -- tools/swift_migration/whole_suite.sh`, say) finds
the lock held for it and does not wait for its own parent.

lock runs COMMAND under the lock with its stdio inherited (no watchdog):
whole_suite.sh uses it around tools/run_tests.expect, which has its own
stall watchdog. On INT, TERM or HUP the command gets SIGTERM first, so that
its own cleanup runs (run_tests.expect's trap kills what it spawned), for
up to --term-grace seconds (default 30); then SIGKILL to its process group
and to every process still below it (expect's spawn puts xcodebuild in a
session of its own, which the group kill does not reach); then the test
hosts of --host-prefix, by run's identification (launchd starts them, so
nothing above reaches them); the lock is released only after all that.
The same hosts are killed after a normal end. With --stall-reports GLOB,
a file matching GLOB that appears during a run that fails (the list of
existing ones is taken once the lock is held) makes the status 124:
run_tests.expect's watchdog writes tmp/test-stall-<time>.txt and exits 1.
hold takes the lock and keeps it until process PID ends (or INT, TERM or
HUP), printing SWIFT_MIGRATION_SUITE_LOCK_HELD=<value> once it is held; a
script exports that so that its own whole-suite steps find the lock held
for them (coverage_tests.sh --per-class holds it across all its classes). status prints the holder, or that the lock is
free. Neither reads the load average or free memory: this is sequencing,
not a load threshold.

wait (for the nightly session, which must never wait on a background job
without a bound): returns 0 as soon as process PID has exited (at once,
saying so, if no such process is running), or 3 (EXIT_STILL_RUNNING) when N
seconds have passed and it is still running. It waits on the kernel's exit event (kqueue), not
by polling. Run it in the foreground with a Bash timeout above N, then look
at the clock before waiting again.

Signals: INT, TERM and HUP sent to run kill COMMAND's process group
(SIGKILL) and this run's test hosts, then exit 128 + the signal. Sent to
lock, they give COMMAND SIGTERM and up to --term-grace seconds to clean up,
then SIGKILL to what is left and the hosts of --host-prefix (above), then
exit 128 + the signal; a second signal during the grace is ignored, and a
signal that arrives after COMMAND ended is recorded without cutting the
cleanup short.

Exit status: run and lock, COMMAND's status (128 + N if a signal N ended
it), 124 for a stall, 75 when --no-wait finds the lock held; status, 0
free, 1 held; wait, 0 ended (or no such process), 3 still running; 2 for a
usage error (wait: also a pid that cannot be watched).
"""

import argparse
import collections
import ctypes
import datetime as dt
import fcntl
import json
import os
import re
import select
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import deadline_run as dr  # noqa: E402
import test_load_profile as tlp  # noqa: E402

EXIT_USAGE = 2
EXIT_STILL_RUNNING = 3
EXIT_LOCK_BUSY = 75
EXIT_STALLED = 124

LOCK_ENV = 'SWIFT_MIGRATION_SUITE_LOCK'
HELD_ENV = 'SWIFT_MIGRATION_SUITE_LOCK_HELD'
DEFAULT_LOCK = os.path.join(os.path.expanduser('~'), 'Library', 'Caches',
                            'com.googlecode.iterm2.swift-migration', 'whole-suite.lock')

SAMPLE_SECONDS = 3
SAMPLE_TIMEOUT = 30
COMMAND_TIMEOUT = 20
MAX_SAMPLED_HOSTS = 8
LOG_TAIL_LINES = 300
# After COMMAND exits, output that is still arriving (a pipe another
# process holds open) is read for at most this long.
DRAIN_SECONDS = 5.0


def say(message):
    print('suite_guard: %s' % message, file=sys.stderr, flush=True)


def now_text():
    return dt.datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')


# --- The lock ----------------------------------------------------------------

def lock_path():
    return os.environ.get(LOCK_ENV) or DEFAULT_LOCK


def pid_alive(pid, start=None):
    info = dr.proc_info(pid) if pid else None
    if info is None or info.status == dr.SZOMB:
        return False
    return start is None or info.start == start


def read_holder(path):
    """The holder recorded in the lock file, a dict, or None."""
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return None
    try:
        info = json.loads(text) if text.strip() else None
    except ValueError:
        return None
    return info if isinstance(info, dict) else None


def describe_holder(info, path):
    if not info:
        return 'an unknown process (the lock file names none; find it with: lsof %s)' % path
    pid = info.get('pid')
    alive = pid_alive(pid, info.get('pid_start'))
    return 'pid %s (%s) in %s since %s: %s' % (
        pid, 'running' if alive else 'no longer running', info.get('checkout'),
        info.get('started'), info.get('label') or ' '.join(info.get('command') or []))


class SuiteLock:
    """The machine-wide whole-suite lock: flock(2) on lock_path()."""

    def __init__(self, path=None):
        self.path = path or lock_path()
        self.fd = None
        self.nested = False
        self.waited = 0.0

    def held_by_ancestor(self):
        held = os.environ.get(HELD_ENV, '')
        pid_text, _, path = held.partition(':')
        if not pid_text.isdigit() or path != self.path:
            return False
        info = read_holder(self.path)
        return (info is not None and info.get('pid') == int(pid_text)
                and pid_alive(int(pid_text), info.get('pid_start')))

    def acquire(self, label, command, wait=True):
        """True when held (or held by an ancestor); False only when wait is
        false and another run holds it."""
        if self.held_by_ancestor():
            self.nested = True
            say('the whole-suite lock is already held for this run by pid %s; not taken again'
                % os.environ[HELD_ENV].partition(':')[0])
            return True
        directory = os.path.dirname(self.path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            holder = describe_holder(read_holder(self.path), self.path)
            if not wait:
                os.close(fd)
                say('the whole-suite lock (%s) is held by %s; --no-wait, so not waiting'
                    % (self.path, holder))
                return False
            say('waiting for the whole-suite lock (%s), held by %s' % (self.path, holder))
            began = time.monotonic()
            fcntl.flock(fd, fcntl.LOCK_EX)
            self.waited = time.monotonic() - began
            say('got the whole-suite lock after %d seconds' % self.waited)
        previous = read_holder(self.path)
        if previous and previous.get('pid') and not pid_alive(previous.get('pid'), previous.get('pid_start')):
            say('recovered the whole-suite lock from pid %s (%s, since %s), which is gone'
                % (previous.get('pid'), previous.get('label'), previous.get('started')))
        me = dr.proc_info(os.getpid())
        record = {'pid': os.getpid(), 'pid_start': me.start if me else None, 'checkout': ROOT,
                  'label': label, 'command': list(command), 'started': now_text()}
        os.ftruncate(fd, 0)
        os.pwrite(fd, (json.dumps(record) + '\n').encode(), 0)
        self.fd = fd
        return True

    def child_env(self, env):
        env = dict(env)
        if self.fd is not None:
            env[HELD_ENV] = '%d:%s' % (os.getpid(), self.path)
        return env

    def release(self):
        if self.fd is None:
            return
        # Emptied while still held, so a later holder's record is never
        # erased.
        try:
            os.ftruncate(self.fd, 0)
            fcntl.flock(self.fd, fcntl.LOCK_UN)
        finally:
            os.close(self.fd)
            self.fd = None


# --- Test hosts --------------------------------------------------------------

class Hosts:
    """This run's test hosts: path under a prefix, the test host executable,
    -suite iterm2-tests among the arguments, and not older than the run."""

    def __init__(self, prefixes):
        self.prefixes = [os.path.join(os.path.realpath(p), '') for p in prefixes]
        self.proc = tlp.Libproc()
        self.existing = set()
        self.seen = set()

    def exclude_existing(self):
        self.existing = set(dr.all_pids())

    def is_host(self, pid):
        if not self.prefixes or pid in self.existing:
            return False
        if not tlp.is_test_host_path(self.proc.path(pid), self.prefixes):
            return False
        return tlp.has_test_host_suite(self.proc.args(pid))

    def find(self):
        found = [pid for pid in dr.all_pids() if self.is_host(pid)]
        self.seen.update(found)
        return sorted(found)

    def kill(self, bound=10.0):
        """SIGKILL to every host of this run, each checked again just
        before; waits up to bound seconds for them to go."""
        targets = set(self.find()) | self.seen
        killed = []
        for pid in sorted(targets):
            if self.is_host(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                    killed.append(pid)
                except (ProcessLookupError, PermissionError):
                    pass
        end = time.monotonic() + bound
        while time.monotonic() < end and any(pid_alive(p) for p in killed):
            time.sleep(0.05)
        return killed


# --- Watching the result bundle -----------------------------------------------

# A line of a test host's output that marks test progress: a test case or a
# suite starting or ending (any result wording; a result ends with its
# duration).
TEST_EVENT = re.compile(r"^(Test Case '[^']+' (started\.|.+ \([0-9.]+ seconds\)\.?)"
                        r"|Test Suite '[^']+' (started|passed|failed) at )")
STARTED_EVENT = re.compile(r"^(Test Case '[^']+' started\.|Test Suite '[^']+' started at )")
SESSION_PID = re.compile(r'Test process runnable PID is ([0-9]+)')
STAGING = os.path.join('Staging', '1_Test', 'Diagnostics')
OUTPUT_NAME = 'StandardOutputAndStandardError.txt'
# How often the result bundle is looked at.
WATCH_INTERVAL = 5.0


class Worker:
    """One test host's directory in the result bundle's staging area:
    <bundle>/Staging/1_Test/Diagnostics/<configuration>/ModernTests-<uuid>/,
    with StandardOutputAndStandardError.txt (everything the host writes,
    the XCTest lines among it, written as it happens) and
    Session-ModernTests-<time>-<id>.log (xcodebuild's log of the session,
    with "Test process runnable PID is NNN")."""

    def __init__(self, directory, now):
        self.dir = directory
        self.output = os.path.join(directory, OUTPUT_NAME)
        self.offset = 0
        self.partial = b''
        self.last_event = None
        self.event_time = now
        self.pid = None
        self.sessions_seen = None

    def name(self):
        return os.path.basename(self.dir.rstrip('/'))

    def poll(self, now):
        """Reads what the host wrote since the last look; True if a test
        event was among it."""
        try:
            size = os.path.getsize(self.output)
        except OSError:
            return False
        if size < self.offset:
            self.offset, self.partial = 0, b''
        if size == self.offset:
            return False
        seen = False
        with open(self.output, 'rb') as f:
            f.seek(self.offset)
            while True:
                chunk = f.read(1 << 20)
                if not chunk:
                    break
                self.offset += len(chunk)
                data = self.partial + chunk
                lines = data.split(b'\n')
                self.partial = lines.pop()[-65536:]
                for raw in lines:
                    line = ANSI.sub('', raw.decode('utf-8', 'replace')).rstrip('\r')
                    if TEST_EVENT.match(line):
                        self.last_event = line
                        seen = True
        if seen:
            self.event_time = now
        return seen

    def host_pid(self):
        """The pid of the host now writing into this directory: the last
        "Test process runnable PID is N" of the newest Session log, read
        again whenever the Session logs change (a restarted host adds one)."""
        sessions = []
        for path in glob_in(self.dir, 'Session-'):
            try:
                st = os.stat(path)
            except OSError:
                continue
            sessions.append((st.st_mtime, os.path.basename(path), st.st_size, path))
        sessions.sort()
        key = tuple(item[:3] for item in sessions)
        if key != self.sessions_seen:
            self.sessions_seen = key
            pid = None
            for item in sessions:
                for line in read_lines(item[3]):
                    m = SESSION_PID.search(line)
                    if m:
                        pid = int(m.group(1))
            self.pid = pid
        return self.pid

    def in_test(self):
        return bool(self.last_event and STARTED_EVENT.match(self.last_event))

    def stuck_for(self, now):
        """Seconds this worker has been inside one test (or one class's
        setup) with no other test event, its host (the newest of the
        directory) still alive; 0 if not. A host that died in its worker's
        last test and was not replaced is not stuck; a replaced one writes
        a Session log and test events of its own and is judged afresh."""
        if not self.in_test():
            return 0
        pid = self.host_pid()
        if pid is not None and not pid_alive(pid):
            return 0
        return now - self.event_time

    def describe(self, now):
        pid = self.host_pid()
        try:
            st = os.stat(self.output)
            size = '%d bytes, last written %s' % (st.st_size, time.strftime('%H:%M:%S', time.localtime(st.st_mtime)))
        except OSError:
            size = 'no output file'
        state = ('in progress for %d seconds: %s' % (now - self.event_time, self.last_event) if self.in_test()
                 else 'between tests; last test event %d seconds ago: %s'
                 % (now - self.event_time, self.last_event or '(none yet)'))
        return 'worker %s, host pid %s (%s): %s; output %s' % (
            self.name(), pid if pid is not None else 'unknown',
            'running' if pid is not None and pid_alive(pid) else 'not running' if pid is not None else '?',
            state, size)


def glob_in(directory, prefix):
    try:
        return [os.path.join(directory, n) for n in os.listdir(directory) if n.startswith(prefix)]
    except OSError:
        return []


class BundleWatch:
    """The test hosts' output in a result bundle that xcodebuild is writing
    (-resultBundlePath): the progress signal of the stall watchdog."""

    def __init__(self, path):
        self.path = path
        self.workers = {}

    def poll(self, now):
        """Looks at every worker; True if any wrote a test event."""
        seen = False
        top = os.path.join(self.path, STAGING)
        for configuration in glob_in(top, ''):
            for directory in glob_in(configuration, 'ModernTests-'):
                if not os.path.exists(os.path.join(directory, OUTPUT_NAME)):
                    continue
                worker = self.workers.get(directory)
                if worker is None:
                    worker = self.workers[directory] = Worker(directory, now)
                if worker.poll(now):
                    seen = True
        return seen

    def stuck(self, now, bound):
        return [w for w in self.workers.values() if w.stuck_for(now) >= bound]


# --- Reading the log ---------------------------------------------------------

ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
SERIAL_START = re.compile(r"^Test Case '(-\[[^']+\])' started\.$")
SERIAL_RESULT = re.compile(r"^Test Case '(-\[[^']+\])' .+ \([0-9.]+ seconds\)\.?$")
PARALLEL_SUITE = re.compile(r"^Test suite '([^']+)' (started|passed|failed) on '(.+)'")
PARALLEL_RESULT = re.compile(r"^Test case '([^']+)' (.+?) on '(.+)' \([0-9.]+ seconds\)\.?$")
END_OF_TESTING = re.compile(r"^(\*\* TEST [A-Z ]+ \*\*|Test session results)")


def is_log_test_event(line):
    """A line of xcodebuild's own output that marks test progress: the
    serial forms of TEST_EVENT, or a parallel run's result or suite line."""
    line = ANSI.sub('', line).rstrip('\r\n')
    return bool(TEST_EVENT.match(line) or PARALLEL_RESULT.match(line) or PARALLEL_SUITE.match(line))


def in_progress_from_log(lines):
    """(serial, parallel, ended): the serial tests started without a result,
    in order; for each parallel worker (name, open class or None, last
    finished test or None); and whether the end of testing was printed."""
    started = collections.OrderedDict()
    workers = collections.OrderedDict()
    ended = False
    for raw in lines:
        line = ANSI.sub('', raw).rstrip('\r\n')
        m = SERIAL_START.match(line)
        if m:
            started[m.group(1)] = True
            continue
        m = SERIAL_RESULT.match(line)
        if m:
            started.pop(m.group(1), None)
            continue
        m = PARALLEL_SUITE.match(line)
        if m:
            name, what, worker = m.groups()
            state = workers.setdefault(worker, {'open': None, 'last': None})
            if what == 'started':
                state['open'] = name
            elif state['open'] == name:
                state['open'] = None
            continue
        m = PARALLEL_RESULT.match(line)
        if m:
            test, status, worker = m.groups()
            state = workers.setdefault(worker, {'open': None, 'last': None})
            state['last'] = '%s (%s)' % (test, status)
            continue
        if END_OF_TESTING.match(line):
            ended = True
    parallel = [(w, s['open'], s['last']) for w, s in workers.items()]
    return list(started), parallel, ended


def test_from_sample(text):
    """The innermost ModernTests frame on the main thread of a `sample`
    report, or None (as tools/report_test_stall.sh reads it)."""
    in_main = False
    found = None
    for line in text.splitlines():
        if 'DispatchQueue_1: com.apple.main-thread' in line:
            in_main = True
            continue
        if in_main and 'Thread_' in line:
            break
        if in_main and '(in ModernTests)' in line:
            found = line
    if found is None:
        return None
    found = re.sub(r'^[ +!:|]*[0-9]+ ', '', found)
    return re.sub(r' \(in ModernTests\).*', '', found).strip()[:200]


def tail_lines(path, count):
    tail = collections.deque(maxlen=count)
    try:
        with open(path, errors='replace') as f:
            for line in f:
                tail.append(line)
    except OSError:
        pass
    return list(tail)


def read_lines(path):
    try:
        with open(path, errors='replace') as f:
            for line in f:
                yield line
    except OSError:
        return


# --- Diagnosis ---------------------------------------------------------------

# Set by a signal: the diagnosis and the command it is running stop at once.
ABORT = threading.Event()
ABORT_POLL = 0.25


class Aborted(Exception):
    pass


def wait_bounded(p, timeout):
    """Waits for p up to timeout seconds, in slices so that ABORT is seen
    promptly; kills its group and raises Aborted on ABORT, returns False on
    timeout (the group killed), True when it ended."""
    end = time.monotonic() + timeout
    while True:
        if ABORT.is_set():
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            raise Aborted()
        left = end - time.monotonic()
        if left <= 0:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            return False
        try:
            p.wait(timeout=min(ABORT_POLL, left))
            return True
        except subprocess.TimeoutExpired:
            pass


def bounded(argv, timeout, out_path=None):
    """Runs argv for at most timeout seconds (killing its process group
    after), its output to out_path (appended) or returned. Raises Aborted
    on a signal; otherwise never raises."""
    if ABORT.is_set():
        raise Aborted()
    try:
        if out_path:
            with open(out_path, 'a') as out:
                out.write('$ %s\n' % ' '.join(argv))
                out.flush()
                p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                                     start_new_session=True)
                if not wait_bounded(p, timeout):
                    out.write('(killed after %d seconds)\n' % timeout)
                out.write('(exit status %s)\n\n' % p.returncode)
            return ''
        import tempfile
        with tempfile.TemporaryFile() as tmp:
            p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=tmp, stderr=subprocess.STDOUT,
                                 start_new_session=True)
            finished = wait_bounded(p, timeout)
            tmp.seek(0)
            text = tmp.read().decode('utf-8', 'replace')
        if not finished:
            text += '\n(killed after %d seconds)\n' % timeout
        return text
    except (OSError, ProcessLookupError) as e:
        if out_path:
            try:
                with open(out_path, 'a') as out:
                    out.write('(could not run %s: %s)\n\n' % (argv[0], e))
            except OSError:
                pass
        return '(could not run %s: %s)\n' % (argv[0], e)


RUSAGE_INFO_V0 = 0
_libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
_libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
_libproc.proc_pid_rusage.restype = ctypes.c_int


def footprint(pid):
    """phys_footprint in bytes (rusage_info_v0), or None."""
    buf = ctypes.create_string_buffer(512)
    if _libproc.proc_pid_rusage(pid, RUSAGE_INFO_V0, buf) != 0:
        return None
    # ri_uuid[16], then seven 64-bit fields before ri_phys_footprint.
    return int.from_bytes(buf.raw[72:80], sys.byteorder)


def write_processes(path, proc):
    text = bounded(['ps', '-axo', 'pid,ppid,pgid,user,stat,%cpu,%mem,rss,etime,command'], COMMAND_TIMEOUT)
    rows = []
    uid = os.getuid()
    for pid in dr.all_pids():
        info = dr.proc_info(pid)
        if info is None or info.uid != uid:
            continue
        task = proc.task(pid)
        rows.append((footprint(pid) or 0, pid, task[1] if task else None, dr.command_line(pid)[:200]))
    rows.sort(reverse=True)
    with open(path, 'w') as f:
        f.write('Every process (ps), at %s:\n' % now_text())
        f.write(text)
        f.write('\nThis user\'s processes, largest memory footprint first:\n')
        f.write('%8s %10s %8s  %s\n' % ('pid', 'footprMB', 'threads', 'command'))
        for fp, pid, threads, line in rows:
            f.write('%8d %10.1f %8s  %s\n' % (pid, fp / 1048576.0, '-' if threads is None else threads, line))


def thread_count(pid):
    """`ps -M -p PID | wc -l` less the header line, bounded; None if ps
    failed."""
    text = bounded(['ps', '-M', '-p', str(pid)], COMMAND_TIMEOUT)
    lines = [line for line in text.splitlines() if line.strip()]
    return len(lines) - 1 if len(lines) > 1 else None


def diagnose(stall_dir, log, hosts, bundle=None, budget=240.0):
    """Records what is needed to understand the stall; returns the lines
    naming the tests in progress. Bounded by budget seconds in all; raises
    Aborted promptly on a signal."""
    began = time.monotonic()

    def left():
        if ABORT.is_set():
            raise Aborted()
        return budget - (time.monotonic() - began)
    os.makedirs(stall_dir, exist_ok=True)
    now = time.monotonic()
    worker_lines = []
    if bundle is not None:
        bundle.poll(now)
        worker_lines = [w.describe(now) for w in sorted(bundle.workers.values(), key=Worker.name)]
        with open(os.path.join(stall_dir, 'workers.txt'), 'w') as f:
            f.write('Result bundle: %s\n' % bundle.path)
            f.write(''.join(line + '\n' for line in worker_lines) or 'no worker directory in its staging area\n')
    pids = hosts.find()
    with open(os.path.join(stall_dir, 'hosts.txt'), 'w') as f:
        for pid in pids:
            threads = thread_count(pid) if left() > COMMAND_TIMEOUT else None
            f.write('%d threads=%s %s\n' % (pid, '?' if threads is None else threads, dr.command_line(pid)))
    from_stacks = []
    for pid in pids[:MAX_SAMPLED_HOSTS]:
        if left() < SAMPLE_TIMEOUT:
            break
        out = os.path.join(stall_dir, 'sample-%d.txt' % pid)
        bounded(['sample', str(pid), str(SAMPLE_SECONDS), '-mayDie', '-file', out], SAMPLE_TIMEOUT)
        try:
            with open(out, errors='replace') as f:
                test = test_from_sample(f.read())
        except OSError:
            test = None
        from_stacks.append((pid, test))
    if left() > COMMAND_TIMEOUT:
        write_processes(os.path.join(stall_dir, 'processes.txt'), hosts.proc)
    memory = os.path.join(stall_dir, 'memory.txt')
    for argv in (['memory_pressure', '-Q'], ['vm_stat'],
                 ['sysctl', 'vm.swapusage', 'kern.memorystatus_vm_pressure_level']):
        if left() > COMMAND_TIMEOUT:
            bounded(argv, COMMAND_TIMEOUT, memory)
    lines = list(worker_lines)
    if log:
        with open(os.path.join(stall_dir, 'log-tail.txt'), 'w') as f:
            f.writelines(tail_lines(log, LOG_TAIL_LINES))
        serial, parallel, ended = in_progress_from_log(read_lines(log))
        if ended:
            lines.append('The log already shows the end of testing: xcodebuild stalled after the tests.')
        for name in serial:
            lines.append('in progress (log): %s' % name)
        for worker, open_class, last in parallel:
            lines.append('worker %s: class in progress (log): %s; last test finished: %s'
                         % (worker, open_class or 'none', last or 'none'))
    for pid, test in from_stacks:
        lines.append('test host %d: innermost test frame on the main thread: %s'
                     % (pid, test or '(none)'))
    if not pids:
        lines.append('no test host of this run was running')
    with open(os.path.join(stall_dir, 'in-progress.txt'), 'w') as f:
        f.write(''.join(line + '\n' for line in lines))
    return lines


# --- run ---------------------------------------------------------------------

class Output:
    """Copies COMMAND's output to stdout and the log; on a terminal, strips
    the carriage returns at the end of each line."""

    def __init__(self, log, pty_mode):
        self.log = open(log, 'ab') if log else None
        self.pty_mode = pty_mode
        self.pending = b''
        self.stdout_ok = True
        self.scan = b''

    def emit(self, data):
        if not data:
            return
        if self.stdout_ok:
            try:
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            except (BrokenPipeError, OSError):
                self.stdout_ok = False
        if self.log:
            self.log.write(data)
            self.log.flush()

    def feed(self, chunk):
        """Copies chunk out; True if it completed a line that is a test
        event (is_log_test_event)."""
        data = self.scan + chunk
        lines = data.split(b'\n')
        self.scan = lines.pop()[-65536:]
        event = any(is_log_test_event(raw.decode('utf-8', 'replace')) for raw in lines)
        if not self.pty_mode:
            self.emit(chunk)
            return event
        data = self.pending + chunk
        cut = data.rfind(b'\n') + 1
        self.pending = data[cut:]
        self.emit(re.sub(rb'\r+\n', b'\n', data[:cut]))
        return event

    def close(self):
        if self.pending:
            self.emit(self.pending.rstrip(b'\r'))
            self.pending = b''
        if self.log:
            self.log.close()


def run(args, command):
    lock = None
    if args.lock:
        lock = SuiteLock()
        if not lock.acquire(args.label or ' '.join(command), command, wait=not args.no_wait):
            return EXIT_LOCK_BUSY
    try:
        if lock is not None and args.lock_wait_file:
            with open(args.lock_wait_file, 'w') as f:
                f.write('%d\n' % round(lock.waited))
        return run_watched(args, command, lock)
    finally:
        if lock is not None:
            lock.release()


def run_watched(args, command, lock):
    hosts = Hosts(args.host_prefix or [])
    hosts.exclude_existing()
    env = lock.child_env(os.environ) if lock else dict(os.environ)
    # The lock's descriptor is not passed on: only this program holds it
    # (the header says why).
    if args.pty:
        import pty
        master, slave = pty.openpty()
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave,
                                start_new_session=True, env=env)
        os.close(slave)
        fd = master
    else:
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True, env=env)
        fd = proc.stdout.fileno()

    def kill_group():
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    try:
        if args.pgid_file:
            with open(args.pgid_file, 'w') as f:
                f.write('%d\n' % proc.pid)
        return watch(args, proc, fd, hosts, kill_group)
    except BaseException:
        # Whatever went wrong here, the command and its hosts do not
        # outlive this program.
        kill_group()
        hosts.kill()
        raise
    finally:
        if args.pgid_file:
            try:
                os.remove(args.pgid_file)
            except OSError:
                pass


def watch(args, proc, fd, hosts, kill_group):
    out = Output(args.log, args.pty)
    # A self-pipe written when COMMAND exits or a signal arrives, so the
    # loop sleeps in select on output and those alone, with the stall bound
    # (and the bundle's look interval) as its only timeout.
    wake_r, wake_w = os.pipe()
    exited = threading.Event()

    def waiter():
        proc.wait()
        exited.set()
        os.write(wake_w, b'x')
    threading.Thread(target=waiter, daemon=True).start()
    got_signal = {'n': None}

    def on_signal(signum, frame):
        got_signal['n'] = signum
        ABORT.set()
        os.write(wake_w, b's')
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, on_signal)

    bundle = BundleWatch(args.result_bundle) if args.result_bundle else None
    last_progress = time.monotonic()
    next_look = last_progress + WATCH_INTERVAL
    # Until the first test event any output is progress (the build of
    # `xcodebuild test`, the hosts starting); from then on only test events.
    tests_started = False
    stalled = None
    drain_end = None
    open_fd = True
    while open_fd:
        if got_signal['n'] is not None:
            break
        now = time.monotonic()
        if drain_end is None and exited.is_set():
            drain_end = now + DRAIN_SECONDS
        if drain_end is None and args.stall_seconds:
            if bundle is not None and now >= next_look:
                next_look = now + WATCH_INTERVAL
                if bundle.poll(now):
                    last_progress = now
                    tests_started = True
                stuck = bundle.stuck(now, args.stall_seconds)
                if stuck:
                    stalled = ('worker %s has been inside one test for %d seconds with no other test event'
                               % (stuck[0].name(), stuck[0].stuck_for(now)))
                    break
            if now - last_progress >= args.stall_seconds:
                stalled = ('no test progress for %d seconds: %s'
                           % (args.stall_seconds,
                              'no test event from xcodebuild%s' % (' or any test host' if bundle is not None
                                                                     else '')
                              if tests_started else 'no output from xcodebuild before the tests began'))
                break
        timeouts = []
        if drain_end is not None:
            timeouts.append(drain_end - now)
        elif args.stall_seconds:
            timeouts.append(args.stall_seconds - (now - last_progress))
            if bundle is not None:
                timeouts.append(next_look - now)
        timeout = max(0.0, min(timeouts)) if timeouts else None
        try:
            ready, _, _ = select.select([fd, wake_r], [], [], timeout)
        except InterruptedError:
            continue
        if wake_r in ready:
            os.read(wake_r, 64)
        if fd in ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b''
            if not chunk:
                open_fd = False
            else:
                event = out.feed(chunk)
                if event:
                    tests_started = True
                if event or not tests_started:
                    last_progress = time.monotonic()
            continue
        if drain_end is not None and time.monotonic() >= drain_end:
            break
    if stalled:
        out.close()
        return stall(args, proc, hosts, kill_group, bundle, stalled, got_signal)
    if got_signal['n'] is not None:
        say('received signal %d; killing the test command and this run\'s test hosts' % got_signal['n'])
        kill_group()
        hosts.kill()
        out.close()
        return 128 + got_signal['n']
    # Ended by itself: read what is left, then the status.
    out.close()
    proc.wait()
    killed = hosts.kill()
    if killed:
        say('killed test hosts left by the run: %s' % ' '.join(map(str, killed)))
    code = proc.returncode
    return 128 - code if code < 0 else code


def stall(args, proc, hosts, kill_group, bundle, why, got_signal):
    stall_dir = args.stall_dir or os.path.join(os.path.dirname(os.path.abspath(args.log or '.')), 'stall')
    print('\n*** The run looks stalled (--stall-seconds %d): %s. Recording what each test host '
          'was doing in %s before killing the run. ***' % (args.stall_seconds, why, stall_dir), flush=True)
    try:
        lines = diagnose(stall_dir, args.log, hosts, bundle)
    except Aborted:
        say('received signal %d during the diagnosis; killing the test command and this run\'s test hosts'
            % got_signal['n'])
        kill_group()
        hosts.kill()
        return 128 + got_signal['n']
    except Exception as e:  # The diagnosis must never keep the run alive.
        lines = ['the diagnosis failed: %r' % e]
    kill_group()
    killed = hosts.kill()
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        pass
    text = ['STALLED at %s: %s (suite_guard.py --stall-seconds %d). '
            'The test command was killed (process group %d), and this run\'s test hosts: %s.'
            % (now_text(), why, args.stall_seconds, proc.pid, ' '.join(map(str, killed)) or 'none'),
            'Tests in progress:'] + ['  ' + line for line in lines] + [
            'Records in %s: hosts.txt, sample-<pid>.txt, processes.txt, memory.txt, log-tail.txt, '
            'workers.txt, in-progress.txt.' % stall_dir]
    try:
        os.makedirs(stall_dir, exist_ok=True)
        with open(os.path.join(stall_dir, 'stall.txt'), 'w') as f:
            f.write('\n'.join(text) + '\n')
    except OSError:
        pass
    print('\n'.join('*** ' + line for line in text), flush=True)
    return EXIT_STALLED


# --- lock, status, wait ------------------------------------------------------

def descendants(pid):
    """Every live process below pid, by parent pid, deepest last."""
    children = {}
    for p in dr.all_pids():
        info = dr.proc_info(p)
        if info is not None and info.status != dr.SZOMB:
            children.setdefault(info.ppid, []).append(p)
    found, stack = [], list(children.get(pid, []))
    while stack:
        p = stack.pop()
        found.append(p)
        stack.extend(children.get(p, []))
    return found


def stall_reports(pattern):
    import glob
    return set(glob.glob(pattern)) if pattern else set()


def run_locked(args, command):
    """lock: COMMAND under the lock. On INT, TERM or HUP the command gets
    SIGTERM first, so that its own cleanup runs (run_tests.expect's trap
    kills what it spawned), up to --term-grace seconds; then SIGKILL to its
    process group and to every process still below it (expect's `spawn`
    puts xcodebuild in a session of its own, out of the group's reach);
    then this checkout's test hosts (--host-prefix: the same
    identification as run, never by name alone), which nothing above
    reaches (launchd starts them); and only then is the lock released."""
    lock = SuiteLock()
    if not lock.acquire(args.label or ' '.join(command), command, wait=not args.no_wait):
        return EXIT_LOCK_BUSY
    try:
        # Taken once the lock is held, so that a report another run wrote
        # while this one waited is not taken for this run's.
        before = stall_reports(args.stall_reports)
        hosts = Hosts(args.host_prefix or [])
        hosts.exclude_existing()
        # Installed before the command starts. A signal is recorded; it
        # interrupts only the wait for the command, so that the cleanup
        # after it (the hosts, the stall reports) always runs to the end.
        got = {'n': None}
        state = {'waiting': False}

        def on_signal(signum, frame):
            if got['n'] is None:
                got['n'] = signum
                if state['waiting']:
                    raise Interrupted()
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, on_signal)
        proc = subprocess.Popen(command, start_new_session=True, env=lock.child_env(os.environ))
        code = None
        try:
            if got['n'] is None:
                state['waiting'] = True
                code = proc.wait()
                state['waiting'] = False
        except Interrupted:
            state['waiting'] = False
            code = proc.poll()
        if got['n'] is not None and code is None:
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                signal.signal(sig, signal.SIG_IGN)
            say('received signal %d; sending SIGTERM to the command so that its own cleanup runs '
                '(up to %d seconds)' % (got['n'], args.term_grace))
            try:
                os.kill(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=args.term_grace)
            except subprocess.TimeoutExpired:
                say('the command is still running after %d seconds; killing it and everything below it'
                    % args.term_grace)
            # Whatever its cleanup left: its group, and what is below it in
            # sessions of its own (expect's spawn).
            left = descendants(proc.pid)
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            for p in left:
                try:
                    os.kill(p, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
            if proc.poll() is None:
                proc.wait()
        killed = hosts.kill()
        if killed:
            say("killed this checkout's test hosts: %s" % ' '.join(map(str, killed)))
        if got['n'] is not None:
            return 128 + got['n']
        code = 128 - code if code < 0 else code
        new = sorted(stall_reports(args.stall_reports) - before)
        if new and code != 0:
            say("the command's stall watchdog stopped the run; its report: %s" % ' '.join(new))
            return EXIT_STALLED
        return code
    finally:
        lock.release()


class Interrupted(Exception):
    pass


def hold(args):
    """hold: the lock, held until process --pid ends (or this program gets
    INT, TERM or HUP), for a shell script that runs several whole-suite
    steps in a row (coverage_tests.sh --per-class). Once held, prints
    SWIFT_MIGRATION_SUITE_LOCK_HELD=<value> on stdout: with that in their
    environment, the script's steps find the lock held for them."""
    lock = SuiteLock()
    if not lock.acquire(args.label or 'hold for pid %d' % args.pid, ['hold', str(args.pid)],
                        wait=not args.no_wait):
        return EXIT_LOCK_BUSY
    try:
        # Nested (an ancestor holds the lock): pass its value on unchanged,
        # so that the steps below find the lock their ancestor holds.
        value = os.environ[HELD_ENV] if lock.nested else '%d:%s' % (os.getpid(), lock.path)
        print('%s=%s' % (HELD_ENV, value), flush=True)
        try:
            sys.stdout.close()
        except OSError:
            pass

        def on_signal(signum, frame):
            raise Interrupted()
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, on_signal)
        kq = select.kqueue()
        try:
            event = select.kevent(args.pid, filter=select.KQ_FILTER_PROC,
                                  flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)
            try:
                kq.control([event], 1, None)
            except (ProcessLookupError, OSError, Interrupted):
                pass
        finally:
            kq.close()
        return 0
    finally:
        lock.release()


def status():
    path = lock_path()
    try:
        fd = os.open(path, os.O_RDWR)
    except FileNotFoundError:
        print('free (%s does not exist)' % path)
        return 0
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print('held by %s' % describe_holder(read_holder(path), path))
        return 1
    finally:
        os.close(fd)
    print('free (%s)' % path)
    return 0


def wait_pid(pid, seconds):
    kq = select.kqueue()
    try:
        event = select.kevent(pid, filter=select.KQ_FILTER_PROC,
                              flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)
        try:
            got = kq.control([event], 1, seconds)
        except ProcessLookupError:
            print('no process with pid %d is running (it has ended, or never existed)' % pid)
            return 0
        except OSError as e:
            print('pid %d cannot be watched: %s' % (pid, e.strerror or e))
            return EXIT_USAGE
        if got and got[0].flags & select.KQ_EV_ERROR:
            # kqueue reports a pid it cannot watch as an error event.
            if got[0].data == 3:  # ESRCH
                print('no process with pid %d is running (it has ended, or never existed)' % pid)
                return 0
            print('pid %d cannot be watched: %s' % (pid, os.strerror(got[0].data)))
            return EXIT_USAGE
        if got:
            print('pid %d has exited' % pid)
            return 0
        print('pid %d is still running after %d seconds' % (pid, seconds))
        return EXIT_STILL_RUNNING
    finally:
        kq.close()


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    command = []
    if '--' in argv:
        i = argv.index('--')
        argv, command = argv[:i], argv[i + 1:]
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                     epilog='See the top of the file for details.')
    sub = parser.add_subparsers(dest='cmd')
    r = sub.add_parser('run')
    r.add_argument('--stall-seconds', type=int, default=0)
    r.add_argument('--log')
    r.add_argument('--stall-dir')
    r.add_argument('--host-prefix', action='append')
    r.add_argument('--pty', action='store_true')
    r.add_argument('--result-bundle')
    r.add_argument('--pgid-file')
    r.add_argument('--lock', action='store_true')
    r.add_argument('--no-wait', action='store_true')
    r.add_argument('--lock-wait-file')
    r.add_argument('--label')
    k = sub.add_parser('lock')
    k.add_argument('--no-wait', action='store_true')
    k.add_argument('--label')
    k.add_argument('--host-prefix', action='append')
    k.add_argument('--term-grace', type=int, default=30)
    k.add_argument('--stall-reports')
    h = sub.add_parser('hold')
    h.add_argument('--pid', type=int, required=True)
    h.add_argument('--no-wait', action='store_true')
    h.add_argument('--label')
    sub.add_parser('status')
    w = sub.add_parser('wait')
    w.add_argument('--pid', type=int, required=True)
    w.add_argument('--seconds', type=int, required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else EXIT_USAGE
    if args.cmd in ('run', 'lock') and not command:
        say('%s needs a command after --' % args.cmd)
        return EXIT_USAGE
    if args.cmd == 'run':
        if args.stall_seconds < 0:
            say('--stall-seconds takes 0 or more')
            return EXIT_USAGE
        if args.no_wait and not args.lock:
            say('--no-wait applies with --lock')
            return EXIT_USAGE
        return run(args, command)
    if args.cmd == 'lock':
        return run_locked(args, command)
    if args.cmd == 'hold':
        return hold(args)
    if args.cmd == 'status':
        return status()
    if args.cmd == 'wait':
        if args.pid <= 0:
            say('--pid takes a process id above 0')
            return EXIT_USAGE
        if args.seconds < 0:
            say('--seconds takes 0 or more')
            return EXIT_USAGE
        return wait_pid(args.pid, args.seconds)
    parser.print_usage(sys.stderr)
    return EXIT_USAGE


if __name__ == '__main__':
    sys.exit(main())
