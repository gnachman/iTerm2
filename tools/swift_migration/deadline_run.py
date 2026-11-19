#!/usr/bin/env python3
"""Run a command with a hard time limit, then leave nothing of it running.

Part of the Objective-C to Swift migration tooling, used by
nightly_start.sh to cap the length of the unattended orchestrator session.
docs/swift-migration/workflow.md section 4 asks for this: "Until the usage
reading has been proven over several nights, the run is also capped by a
conservative limit on its own length, so that a failure to read usage
cannot spend the week's quota." It also stops the run before the owner's
morning ("Work also stops when the owner starts using the checkout in the
morning") when given --until. macOS only.

The deadline is the earlier of --seconds from now and the next local
--until HH:MM, computed in the local zone (zoneinfo), so a daylight saving
change in between is counted in real seconds.

How the command is started. It is spawned with posix_spawn in its own
session and process group, with SIGINT, SIGTERM, SIGHUP and SIGQUIT reset to
their defaults, and with macOS "responsibility" disclaimed, so that the
kernel records the command as the responsible process of everything it
starts, however deep: a process keeps its responsible pid when it calls
setsid, when it double forks, and when its parent dies and launchd adopts
it. Its environment also gets SWIFT_MIGRATION_NIGHT_ID=<--night-id>, which
every child inherits unless it clears its environment.

At the deadline the command's process group gets SIGINT (a headless Claude
Code run ends its current turn on SIGINT), then after --grace seconds
SIGTERM (Claude Code stops, kills the process tree of a running Bash
command, runs SessionEnd hooks and exits 143), then after --term-grace
seconds SIGKILL. SIGTERM, SIGINT and SIGHUP sent to this runner (for example
by `launchctl kill`) are passed on to the group.

The sweep. When the command has exited, by itself or at the deadline, every
process of the current user that belongs to the run is found and killed:
SIGTERM, then up to --sweep-grace seconds of polling, then SIGKILL for the
survivors. Each pid killed and its command line are logged, and so is any
pid that could not be killed. A process belongs to the run when its
environment contains the exact token SWIFT_MIGRATION_NIGHT_ID=<night id>,
when its responsible pid is the command's pid, or when its responsible pid
is a process already known to belong to the run (see Tracker; the run is
watched once a second for this). Nothing else is touched, and nothing is
matched by command name. Two checks guard against pid reuse: a process
that started before the command is never a target, and a responsible pid
counts only while it still names the process that was seen (same start
time) or no process at all.

A fourth rule: a process whose parent is a process of the run belongs to
it (seen while both run). Under Xcode's /usr/bin/python3 the tools' own
processes are platform binaries whose responsible process is the root, so
once the root has exited only what the watcher saw before is linked; a
daemon such a tool double-forks less than a second before the root exits
stays out of reach (see below). The python.org interpreter makes itself
the responsible process of what it starts and shows its environment, so
there the daemon is found as long as the tool runs.

Why three rules: macOS hides the environment of Apple platform binaries
(/bin/sleep, /bin/sh, /usr/bin/git, xcodebuild) from other processes, so
the marker alone misses them; and it makes an app bundle's executable (for
example Python.app, which the python.org and Homebrew python3 run) the
responsible process of what it starts, so the responsible pid alone misses
those.

What is out of reach: a platform binary (hidden environment) whose
responsible process is a bundle app or a disclaiming process, when the
watcher never saw the two running at the same time (for example a python3
that starts a process in a new session and exits within a second); a
process whose environment is readable but cleared of the marker and that
is not linked by responsibility; a process that clears its
environment and disclaims responsibility; a process started through launchd
or another service on the run's behalf (`open`, `launchctl`, XPC); and a
process of another user.

The tmux mode (--tmux-socket and --tmux-session), which nightly_start.sh
uses: the session is an interactive program in a tmux server on a private
socket, so it outlives the command that starts it. COMMAND is the tmux
client invocation that creates the session (`tmux -S SOCKET new-session -d
-s NAME ...`); it is spawned as above (own session, responsibility
disclaimed, the marker in its environment, which the tmux server it forks
and everything in the session inherit), and must exit 0 with the session
present, else exit status 127. The run then lasts until the session ends,
or the --status-file appears (the session wrapper writes the program's exit
status there when it exits, even if another window keeps the tmux session
alive), or the deadline. The wrapper should keep the pane open after
writing the status (it is closed here): closing the pane hangs up its
terminal, which kills what is left in it before it has been seen, and
macOS then reports their children (in a new session, say) as their own
responsible processes, out of reach of the sweep. While it lasts, the pane is looked at for
--blocked-seconds after the start, and if it shows --blocked-pattern (a
dialog that nobody will answer, such as Claude Code's workspace trust
dialog) the session is stopped at once and the exit status is 122. With
--stall-seconds, a session whose pane does not change and whose
--transcript does not grow for that long from the start (another dialog
nobody will answer) is stopped the same way, exit status 121; the watch
ends once the transcript grows.
In the tmux mode the deadline is the start of the stop sequence, placed
as long before the hard limit as the sequence can take (stop_seconds():
--interrupt-wait + --grace + --term-grace + --sweep-grace + 20), so that
everything is dead by the hard limit; the remaining time is recomputed
from the wall clock each second, since time.monotonic() stops while the
Mac sleeps. The processes signalled by the pane-group kills are itemized
in the log, as the sweep's are. The root file is written by the session's
own wrapper, so the pid it names is adopted only if it descends from the
pane's first process and started after the run.
To stop the session (at the deadline, when blocked, or when this runner
gets SIGTERM, SIGINT or SIGHUP): Escape is sent to the pane (interactive
Claude Code stops the current turn on Esc), then after --interrupt-wait
seconds "/exit" and Enter are typed (Claude Code's command that ends the
session, after its SessionEnd hooks); after --grace more seconds the
pane's process group gets SIGTERM; after --term-grace more seconds the tmux
server is killed (its panes get SIGHUP) and the pane's process group gets
SIGKILL. Then, always, the tmux server on the socket is killed if it is
still there, its socket file removed, and the sweep below runs. The server
and the pane's first process are added to the run's known processes when
the session starts, and so is the process named in --root-file: tmux 3.8
makes every process it starts in a pane its own responsible process, so
inside the pane responsibility links nothing unless the wrapper runs the
program with `deadline_run.py --spawn-root FILE -- PROGRAM`, which spawns
it with responsibility disclaimed (in the same process group, keeping the
terminal) and writes its pid and start time to FILE. Exit status: the number in --status-file if the session
ended by itself; 125 if it ended without one (killed from outside); 124 at
the deadline; 122 if blocked; 121 if stalled at the start; 128 + the signal number if this runner was
signalled; 127 if it could not start.

Usage:
    deadline_run.py --seconds N [--until HH:MM] [--grace S] [--term-grace S]
                    [--night-id ID] [--sweep-grace S]
                    [--now ISO] [--tz ZONE] -- COMMAND [ARG...]
    deadline_run.py --seconds N ... --tmux-socket PATH --tmux-session NAME
                    [--tmux PROGRAM] [--status-file FILE]
                    [--interrupt-wait S] [--blocked-pattern REGEX]
                    [--blocked-seconds S] -- TMUX-CLIENT-COMMAND...
    deadline_run.py --spawn-root FILE -- COMMAND [ARG...]
    deadline_run.py --show-deadline --seconds N [--until HH:MM]
                    [--clean-stop-margin S] [--now ISO] [--tz ZONE]
--show-deadline prints limit_seconds=, stop_seconds=, hard=, stop_start=
(the hard limit minus stop_seconds, computed from the same wait options)
and clean_stop= (the hard limit minus --clean-stop-margin, default 2700
seconds) and exits.
Exit status: the command's own status (128 + signal number if a signal
ended it); 124 if the deadline was reached; 127 if the command could not
be started; 64 for a usage error.
"""

import argparse
import ctypes
import ctypes.util
import datetime as dt
import os
import re
import signal
import subprocess
import struct
import sys
import threading
import time
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

EXIT_DEADLINE = 124
EXIT_CANNOT_START = 127
EXIT_USAGE = 64
EXIT_NO_STATUS = 125
EXIT_BLOCKED = 122
EXIT_STALLED = 121

# Added to the stop sequence's waits when computing when it must start:
# up to 10 seconds of the sweep's wait after SIGKILL, and 10 of slack for
# the tmux commands, the snapshots and the kills themselves.
STOP_SLACK = 20

MARKER = 'SWIFT_MIGRATION_NIGHT_ID'


# Time.

def seconds_until(hhmm, now, zone=None):
    """Seconds from aware `now` to the next HH:MM after it in `zone`.

    `zone` defaults to now's tzinfo; pass the local ZoneInfo when `now`
    carries only a fixed offset. The arithmetic is done in UTC so that a
    clock change in between is counted in real seconds."""
    hour, minute = (int(part) for part in hhmm.split(':'))
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError('time out of range: %r' % hhmm)
    zone = zone or now.tzinfo
    now_utc = now.astimezone(dt.timezone.utc)
    target_date = now.astimezone(zone).date()
    for _ in range(3):
        target = dt.datetime(target_date.year, target_date.month,
                             target_date.day, hour, minute, tzinfo=zone)
        delta = (target.astimezone(dt.timezone.utc) - now_utc).total_seconds()
        if delta > 0:
            return delta
        target_date += dt.timedelta(days=1)
    raise ValueError('no future %s found' % hhmm)


def local_zone(name=None):
    """The local zone as a ZoneInfo: --tz, else TZ, else /etc/localtime."""
    if not name:
        name = os.environ.get('TZ', '').lstrip(':')
    if not name:
        target = os.path.realpath('/etc/localtime')
        if 'zoneinfo/' not in target:
            raise ValueError('cannot find the local time zone; pass --tz')
        name = target.split('zoneinfo/', 1)[1]
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError) as e:
        raise ValueError('unknown time zone %r (%s)' % (name, e))


def parse_now(value, zone):
    if value is None:
        return dt.datetime.now(dt.timezone.utc)
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=zone)
    return parsed


def limit_seconds(seconds, until, now, zone):
    limit = seconds
    if until:
        limit = min(limit, seconds_until(until, now, zone))
    return limit


def fmt(when, zone):
    return when.astimezone(zone).strftime('%Y-%m-%d %H:%M:%S %Z')


def stop_seconds(args):
    """How long the tmux mode's stop sequence can take, start to finish:
    Escape, --interrupt-wait, /exit, --grace, SIGTERM, --term-grace, the
    server kill and SIGKILL, then the sweep (--sweep-grace after SIGTERM,
    up to 10 more after SIGKILL), plus slack. It starts this long before
    the hard limit, so that everything is dead by the hard limit."""
    return (args.interrupt_wait + args.grace + args.term_grace
            + args.sweep_grace + STOP_SLACK)


class Deadline:
    """A deadline on the wall clock. time.monotonic() stops while the
    Mac sleeps, so a deadline counted on it alone would move later by the
    length of every sleep; the remaining time is computed from the wall
    clock each time it is asked for."""

    def __init__(self, seconds, wall=time.time):
        self.wall = wall
        self.at = wall() + seconds

    def remaining(self):
        return self.at - self.wall()


def log(message):
    stamp = dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print('deadline_run %s: %s' % (stamp, message), file=sys.stderr,
          flush=True)


# Processes (macOS).

_libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
_libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
try:
    _responsible = _libc.responsibility_get_pid_responsible_for_pid
    _responsible.restype = ctypes.c_int
    _responsible.argtypes = [ctypes.c_int]
    _disclaim = _libc.responsibility_spawnattrs_setdisclaim
    _disclaim.restype = ctypes.c_int
    _disclaim.argtypes = [ctypes.c_void_p, ctypes.c_int]
except AttributeError:
    _responsible = None
    _disclaim = None

CTL_KERN = 1
KERN_ARGMAX = 8
KERN_PROCARGS2 = 49
PROC_PIDTBSDINFO = 3
PROC_BSDINFO_SIZE = 136
SZOMB = 5
POSIX_SPAWN_SETSIGDEF = 0x04
POSIX_SPAWN_SETSIGMASK = 0x08
POSIX_SPAWN_SETSID = 0x0400


class ProcInfo:
    def __init__(self, pid, ppid, uid, status, start, pgid=None):
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.status = status
        self.start = start  # microseconds since the epoch
        self.pgid = pgid


def proc_info(pid):
    """Kernel facts about pid, or None if it does not exist (or is not
    visible)."""
    buf = ctypes.create_string_buffer(PROC_BSDINFO_SIZE)
    got = _libproc.proc_pidinfo(pid, PROC_PIDTBSDINFO, ctypes.c_uint64(0),
                                buf, PROC_BSDINFO_SIZE)
    if got != PROC_BSDINFO_SIZE:
        return None
    raw = buf.raw
    _flags, status, _xstatus, rpid, ppid, uid = struct.unpack_from('6I', raw)
    # struct proc_bsdinfo: twelve 32-bit fields, pbi_comm[16],
    # pbi_name[32], pbi_nfiles, then pbi_pgid at offset 100.
    pgid = struct.unpack_from('I', raw, 100)[0]
    sec, usec = struct.unpack_from('QQ', raw, 120)
    return ProcInfo(rpid, ppid, uid, status, sec * 1000000 + usec, pgid)


def all_pids():
    count = _libproc.proc_listallpids(None, 0)
    if count <= 0:
        return []
    array = (ctypes.c_int * (count * 2))()
    count = _libproc.proc_listallpids(array, ctypes.sizeof(array))
    return [pid for pid in array[:max(count, 0)] if pid > 0]


def _procargs(pid):
    size = ctypes.c_int(0)
    length = ctypes.c_size_t(ctypes.sizeof(size))
    mib = (ctypes.c_int * 2)(CTL_KERN, KERN_ARGMAX)
    if _libc.sysctl(mib, 2, ctypes.byref(size), ctypes.byref(length),
                    None, 0) != 0:
        return None
    buf = ctypes.create_string_buffer(size.value)
    length = ctypes.c_size_t(size.value)
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
    if _libc.sysctl(mib, 3, buf, ctypes.byref(length), None, 0) != 0:
        return None
    raw = buf.raw[:length.value]
    if len(raw) < 4:
        return None
    argc = struct.unpack_from('i', raw)[0]
    rest = raw[4:]
    nul = rest.find(b'\0')
    if nul < 0:
        return None
    # The executable path, then NUL padding, then argv, then the
    # environment, each string NUL-terminated.
    strings = rest[nul:].lstrip(b'\0').split(b'\0')
    decode = [s.decode('utf-8', 'replace') for s in strings]
    return decode[:argc], [s for s in decode[argc:] if s]


def command_line(pid):
    got = _procargs(pid)
    if got is None or not got[0]:
        return '(command line not readable)'
    return ' '.join(got[0])


def environment_of(pid):
    """The environment strings of pid, or None if they cannot be read. macOS
    returns none for Apple platform binaries, which is also None here."""
    got = _procargs(pid)
    if got is None or not got[1]:
        return None
    return got[1]


def responsible_pid(pid):
    if _responsible is None:
        return None
    got = _responsible(pid)
    return got if got > 0 else None


def same_process(pid, info):
    now = proc_info(pid)
    return (now is not None and now.start == info.start
            and now.status != SZOMB)


# Spawning.

class Child:
    """A spawned command, waited for by a thread so that the main thread
    stays free to run signal handlers."""

    def __init__(self, pid):
        self.pid = pid
        self.returncode = None
        self._done = threading.Event()
        threading.Thread(target=self._wait, daemon=True).start()

    def _wait(self):
        _, status = os.waitpid(self.pid, 0)
        self.returncode = os.waitstatus_to_exitcode(status)
        self._done.set()

    def wait(self, timeout=None):
        """True if the child has exited within timeout seconds."""
        end = None if timeout is None else time.monotonic() + timeout
        while True:
            remaining = None if end is None else end - time.monotonic()
            if remaining is not None and remaining <= 0:
                return self._done.is_set()
            # Short slices so that a signal handler runs promptly.
            if self._done.wait(1.0 if remaining is None
                               else min(1.0, remaining)):
                return True


def spawn(command, env, new_session=True):
    """posix_spawnp in a new session (unless new_session is false),
    signals defaulted, responsibility disclaimed. Returns (Child,
    disclaimed) or raises OSError."""
    attr = ctypes.c_void_p()
    if _libc.posix_spawnattr_init(ctypes.byref(attr)) != 0:
        raise OSError(ctypes.get_errno(), 'posix_spawnattr_init failed')
    try:
        default = 0
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP,
                    signal.SIGQUIT):
            default |= 1 << (sig - 1)
        sigdef = ctypes.c_uint32(default)
        sigmask = ctypes.c_uint32(0)
        _libc.posix_spawnattr_setsigdefault(ctypes.byref(attr),
                                            ctypes.byref(sigdef))
        _libc.posix_spawnattr_setsigmask(ctypes.byref(attr),
                                         ctypes.byref(sigmask))
        flags = POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        if new_session:
            flags |= POSIX_SPAWN_SETSID
        if _libc.posix_spawnattr_setflags(ctypes.byref(attr),
                                          ctypes.c_short(flags)) != 0:
            raise OSError(ctypes.get_errno(), 'posix_spawnattr_setflags')
        disclaimed = (_disclaim is not None
                      and _disclaim(ctypes.byref(attr), 1) == 0)
        argv = (ctypes.c_char_p * (len(command) + 1))(
            *[os.fsencode(a) for a in command], None)
        items = [os.fsencode('%s=%s' % kv) for kv in env.items()]
        envp = (ctypes.c_char_p * (len(items) + 1))(*items, None)
        pid = ctypes.c_int(0)
        err = _libc.posix_spawnp(ctypes.byref(pid), os.fsencode(command[0]),
                                 None, ctypes.byref(attr), argv, envp)
        if err != 0:
            raise OSError(err, os.strerror(err))
        return Child(pid.value), disclaimed
    finally:
        _libc.posix_spawnattr_destroy(ctypes.byref(attr))


def signal_group(pgid, sig):
    try:
        os.killpg(pgid, sig)
        return True
    except (ProcessLookupError, PermissionError):
        return False


# The sweep.

class Tracker:
    """Which processes belong to the run.

    A process of this user that started after the root belongs to the run
    when (1) its environment contains the exact marker token, or (2) its
    responsible pid is the root, or (3) its responsible pid is a process
    already known to belong to the run. Rule 3 is needed because macOS
    hides the environment of Apple platform binaries (rule 1 cannot see
    them) and makes an app bundle's executable, such as Python.app, the
    responsible process of what it starts (rule 2 cannot see those). Once
    a responsible process exits, macOS reports its children as their own
    responsible process, so the link is only visible while both run: known
    processes are remembered by pid and start time, and a process once
    recognized stays recognized. snapshot() is called every second during
    the run, before each signal, and before the final group kill."""

    def __init__(self, root_pid, root_start, night_id):
        self.root_pid = root_pid
        self.root_start = root_start
        self.token = '%s=%s' % (MARKER, night_id)
        # pid -> (start, why); the root itself, so that rule 4 links its
        # children.
        self.known = {root_pid: (root_start, 'the command')}
        self.lock = threading.Lock()

    def adopt(self, pid, why):
        """Remember pid as a process of the run (for example the tmux
        server and the pane's first process, found by asking tmux)."""
        info = proc_info(pid)
        if info is None:
            return False
        with self.lock:
            self.known[pid] = (info.start, why)
        return True

    def _known_as_responsible(self, resp, info):
        entry = self.known.get(resp)
        if entry is None or info.start < entry[0]:
            return False
        now = proc_info(resp)
        # The responsible pid is still that process, or it has gone and
        # no new process has its pid yet; a reused pid does not count.
        return now is None or now.start == entry[0]

    def snapshot(self):
        """Look at every process; return {pid: (ProcInfo, why)} of the live
        processes that belong to the run, and remember them."""
        me = os.getpid()
        uid = os.getuid()
        reuser = proc_info(self.root_pid)
        root_alive_as_itself = (reuser is not None
                                and reuser.start == self.root_start)
        reuse_start = (None if reuser is None or root_alive_as_itself
                       else reuser.start)
        candidates = {}
        for pid in all_pids():
            if pid in (me, self.root_pid):
                continue
            info = proc_info(pid)
            if (info is None or info.uid != uid or info.status == SZOMB
                    or info.start < self.root_start):
                continue
            candidates[pid] = info
        found = {}
        with self.lock:
            for pid, info in candidates.items():
                resp = responsible_pid(pid)
                why = None
                seen = self.known.get(pid)
                if seen is not None and seen[0] == info.start:
                    # Seen before; its responsible pid may since have
                    # changed (macOS reports a process as its own
                    # responsible process once that one has exited).
                    why = seen[1]
                elif resp == self.root_pid and (reuse_start is None
                                              or info.start < reuse_start):
                    why = 'responsible pid %d (the command)' % resp
                else:
                    env = environment_of(pid)
                    if env is not None and self.token in env:
                        why = 'environment %s' % self.token
                if why:
                    found[pid] = (info, why)
                    self.known[pid] = (info.start, why)
            # Rule 3, to a fixed point: a newly known process can be the
            # responsible process of another candidate.
            changed = True
            while changed:
                changed = False
                for pid, info in candidates.items():
                    if pid in found:
                        continue
                    resp = responsible_pid(pid)
                    if (resp is not None and resp != pid
                            and self._known_as_responsible(resp, info)):
                        why = 'responsible pid %d (a process of the run)' % resp
                    elif (info.ppid > 1
                            and self._known_as_responsible(info.ppid, info)):
                        # Rule 4: the parent is a process of the run (seen
                        # while both run). With Xcode's /usr/bin/python3,
                        # whose launcher and interpreter are platform
                        # binaries, this is what links them in the pane.
                        why = 'parent pid %d (a process of the run)' % info.ppid
                    else:
                        continue
                    found[pid] = (info, why)
                    self.known[pid] = (info.start, why)
                    changed = True
        return found


def poll(tracker, stop_event, interval=1.0):
    while not stop_event.wait(interval):
        try:
            tracker.snapshot()
        except Exception as e:  # never let the watcher kill the runner
            log('tracker: snapshot failed: %s' % e)


def sweep(tracker, grace):
    found = tracker.snapshot()
    if not found:
        log('sweep: no process of the run is left')
        return
    lines = {pid: command_line(pid) for pid in found}
    for pid, (info, why) in sorted(found.items()):
        if same_process(pid, info):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except PermissionError as e:
                log('sweep: cannot signal pid %d (%s): %s'
                    % (pid, e, lines[pid]))
    end = time.monotonic() + grace
    pending = dict(found)
    while pending and time.monotonic() < end:
        for pid, (info, why) in list(pending.items()):
            if not same_process(pid, info):
                log('sweep: killed pid %d (SIGTERM; %s): %s'
                    % (pid, why, lines[pid]))
                del pending[pid]
        if pending:
            time.sleep(0.1)
    for pid, (info, why) in sorted(pending.items()):
        if same_process(pid, info):
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
    end = time.monotonic() + 10
    while pending and time.monotonic() < end:
        for pid, (info, why) in list(pending.items()):
            if not same_process(pid, info):
                log('sweep: killed pid %d (SIGKILL; %s): %s'
                    % (pid, why, lines[pid]))
                del pending[pid]
        if pending:
            time.sleep(0.1)
    for pid, (info, why) in sorted(pending.items()):
        log('sweep: COULD NOT KILL pid %d (%s): %s' % (pid, why, lines[pid]))


# The tmux mode.

class Tmux:
    """tmux commands against one server socket and one session; never the
    default socket."""

    def __init__(self, program, socket, name):
        self.program = program
        self.socket = socket
        self.name = name

    def run(self, *args):
        try:
            return subprocess.run([self.program, '-S', self.socket] + list(args),
                                  stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  universal_newlines=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as e:
            return subprocess.CompletedProcess(args, -1, '', str(e))

    def alive(self):
        return self.run('has-session', '-t', '=' + self.name).returncode == 0

    def server_alive(self):
        return self.run('list-sessions').returncode == 0

    def number(self, fmt):
        got = self.run('display-message', '-p', '-t', self.name, fmt)
        try:
            return int(got.stdout.strip())
        except ValueError:
            return None

    def capture(self):
        return self.run('capture-pane', '-p', '-t', self.name).stdout

    def send_keys(self, *keys):
        return self.run('send-keys', '-t', self.name, *keys).returncode == 0

    def kill_server(self):
        return self.run('kill-server').returncode == 0


def read_status(path):
    if not path:
        return None
    try:
        with open(path) as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return None


def run_tmux(args, command, env, limit, night_id, started):
    tmux = Tmux(args.tmux, args.tmux_socket, args.tmux_session)
    stop = {'signal': None}

    def on_signal(signum, frame):
        log('received signal %d; stopping the session' % signum)
        stop['signal'] = signum

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, on_signal)

    def ended():
        return (args.status_file and os.path.exists(args.status_file)) \
            or not tmux.alive()

    try:
        client, disclaimed = spawn(command, env)
    except OSError as e:
        print('deadline_run: cannot start %s: %s' % (command[0], e),
              file=sys.stderr)
        return EXIT_CANNOT_START
    info = proc_info(client.pid)
    root_start = (info.start if info is not None
                  else int((started - 1) * 1000000))
    tracker = Tracker(client.pid, root_start, night_id)
    if not client.wait(60):
        log('the tmux client did not finish within 60 seconds; killing it')
        signal_group(client.pid, signal.SIGKILL)
        client.wait()
    code = client.returncode
    pane_pid = server_pid = None
    if code == 0 and tmux.alive():
        server_pid = tmux.number('#{pid}')
        pane_pid = tmux.number('#{pane_pid}')
        for pid, what in ((server_pid, 'the tmux server'),
                          (pane_pid, "the pane's first process")):
            if pid:
                tracker.adopt(pid, what)
    log('tmux client pid %d exited %s; session %s on %s; server pid %s; '
        'pane pid %s; %s=%s; responsibility %s'
        % (client.pid, code, args.tmux_session, args.tmux_socket, server_pid,
           pane_pid, MARKER, night_id,
           'disclaimed' if disclaimed else 'NOT disclaimed (marker only)'))
    pane_info = proc_info(pane_pid) if pane_pid else None
    adopted = {'root': False}

    def in_pane(pid, info):
        # The session can write the root file, so the pid it names counts
        # only if it is a descendant of the pane's first process (a few
        # generations: session.sh, deadline_run.py --spawn-root, claude)
        # and started after the run did.
        if pane_info is None or info.start < tracker.root_start:
            return False
        for _ in range(6):
            if info is None:
                return False
            if info.ppid == pane_pid:
                return True
            info = proc_info(info.ppid)
        return False

    def adopt_root():
        # The process the session wrapper started with --spawn-root, which
        # disclaimed responsibility: tmux makes every pane process its own
        # responsible process, so without it nothing in the pane would be
        # linked by responsibility.
        if adopted['root'] or not args.root_file:
            return
        try:
            with open(args.root_file) as fh:
                pid, start = (int(x) for x in fh.read().split())
        except (OSError, ValueError):
            return
        now = proc_info(pid)
        if now is not None and now.start == start:
            if in_pane(pid, now):
                with tracker.lock:
                    tracker.known[pid] = (start, 'the session root in the pane')
                log('session root in the pane: pid %d' % pid)
            else:
                log('the root file names pid %d (%s), which is not in the '
                    'pane; ignored' % (pid, command_line(pid)))
        adopted['root'] = True

    def pane_group():
        # The live processes of this user in the pane's process group.
        if pane_info is None:
            return {}
        uid = os.getuid()
        found = {}
        for pid in all_pids():
            info = proc_info(pid)
            if (info is not None and info.pgid == pane_pid
                    and info.uid == uid and info.status != SZOMB
                    and info.start >= tracker.root_start):
                found[pid] = (info, command_line(pid))
        return found

    def signal_pane(sig, name=None):
        # The pane's process group outlives its leader while any member is
        # alive, and its id cannot be reused as a pid until the group is
        # gone, so it is signalled unless another process now has the pid.
        # With a name, the members are itemized in the log, before and
        # (from report_pane) after, as the sweep does.
        if pane_info is None:
            return {}
        now = proc_info(pane_pid)
        if now is None or now.start == pane_info.start:
            members = pane_group() if name else {}
            for pid, (info, line) in sorted(members.items()):
                log('pane group %d: sending %s to pid %d: %s'
                    % (pane_pid, name, pid, line))
            signal_group(pane_pid, sig)
            return members
        return {}

    def report_pane(members, name, wait=0.0):
        end = time.monotonic() + wait
        pending = dict(members)
        while True:
            for pid, (info, line) in list(pending.items()):
                if not same_process(pid, info):
                    log('pane group %d: killed pid %d (%s): %s'
                        % (pane_pid, pid, name, line))
                    del pending[pid]
            if not pending or time.monotonic() >= end:
                break
            time.sleep(0.1)
        for pid, (info, line) in sorted(pending.items()):
            log('pane group %d: pid %d still running after %s: %s'
                % (pane_pid, pid, name, line))

    def finish(result):
        adopt_root()
        tracker.snapshot()
        if tmux.server_alive():
            tmux.kill_server()
            log('killed the tmux server on %s' % args.tmux_socket)
        report_pane(signal_pane(signal.SIGKILL, 'SIGKILL'), 'SIGKILL', 2.0)
        if server_pid:
            server_info = tracker.known.get(server_pid)
            if server_info is not None:
                now = proc_info(server_pid)
                if now is not None and now.start == server_info[0]:
                    try:
                        os.kill(server_pid, signal.SIGKILL)
                    except OSError:
                        pass
        try:
            os.unlink(args.tmux_socket)
        except OSError:
            pass
        sweep(tracker, args.sweep_grace)
        return result

    if code != 0 or (pane_pid is None and not ended()):
        log('the session could not be started (tmux client exit %s)' % code)
        return finish(EXIT_CANNOT_START)

    stop_polling = threading.Event()
    threading.Thread(target=poll, args=(tracker, stop_polling),
                     daemon=True).start()
    # The stop sequence starts early enough to be over by the hard limit.
    stop_len = stop_seconds(args)
    deadline = Deadline(max(0.0, limit - stop_len))
    now_local = dt.datetime.now().astimezone()
    log('hard limit %s; the stop sequence starts at %s (%d seconds before, '
        'the longest it can take)'
        % (fmt(now_local + dt.timedelta(seconds=limit), now_local.tzinfo),
           fmt(now_local + dt.timedelta(seconds=max(0.0, limit - stop_len)),
               now_local.tzinfo), stop_len))
    if stop_len > limit:
        log('the limit (%d seconds) is shorter than the stop sequence; it '
            'starts at once and may end after the limit' % limit)
    watch_until = time.monotonic() + (args.blocked_seconds or 0)
    pattern = re.compile(args.blocked_pattern) if args.blocked_pattern else None

    def transcript_size():
        try:
            return os.path.getsize(args.transcript) if args.transcript else -1
        except OSError:
            return -1

    stall = {'watching': bool(args.stall_seconds), 'screen': None,
             'changed': time.monotonic(), 'size': transcript_size()}

    def stalled():
        # A failed start: since the start, neither the pane's content nor
        # the transcript has changed for --stall-seconds. Watching ends
        # once the transcript grows (the session is working).
        if not stall['watching']:
            return False
        if transcript_size() > stall['size']:
            stall['watching'] = False
            return False
        screen = tmux.capture()
        if screen != stall['screen']:
            stall['screen'] = screen
            stall['changed'] = time.monotonic()
            return False
        return time.monotonic() - stall['changed'] >= args.stall_seconds

    reason = None
    while True:
        adopt_root()
        if stop['signal'] is not None:
            reason = 'signal'
            break
        if ended():
            break
        if pattern is not None and time.monotonic() < watch_until:
            match = pattern.search(tmux.capture())
            if match:
                log('the session is waiting at a dialog nobody will answer '
                    '(the pane shows %r)' % match.group(0))
                reason = 'blocked'
                break
        if stalled():
            log('no progress: the pane has not changed and the transcript '
                '%s has not grown for %d seconds since the start; a failed '
                'start (a dialog nobody will answer?). The screen:\n%s'
                % (args.transcript, args.stall_seconds, stall['screen']))
            reason = 'stalled'
            break
        remaining = deadline.remaining()
        if remaining <= 0:
            reason = 'deadline'
            break
        time.sleep(min(1.0, remaining))

    def wait_end(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if ended():
                return True
            time.sleep(0.2)
        return ended()

    if reason is not None:
        tracker.snapshot()
        log('%s; sending Escape to the session'
            % {'deadline': 'the stop sequence starts (deadline)',
               'signal': 'stopping on a signal',
               'blocked': 'blocked at startup',
               'stalled': 'failed start'}[reason])
        tmux.send_keys('Escape')
        if not wait_end(args.interrupt_wait):
            log('typing /exit')
            tmux.send_keys('-l', '/exit')
            tmux.send_keys('Enter')
            if not wait_end(args.grace):
                tracker.snapshot()
                log("still running; sending SIGTERM to the pane's process "
                    'group %s' % pane_pid)
                members = signal_pane(signal.SIGTERM, 'SIGTERM')
                ok = wait_end(args.term_grace)
                report_pane(members, 'SIGTERM')
                if not ok:
                    tracker.snapshot()
                    log('still running; killing the tmux server')
                    tmux.kill_server()
                    report_pane(signal_pane(signal.SIGKILL, 'SIGKILL'),
                                'SIGKILL', 2.0)
    stop_polling.set()
    status = read_status(args.status_file)
    if reason == 'deadline':
        result = EXIT_DEADLINE
    elif reason == 'blocked':
        result = EXIT_BLOCKED
    elif reason == 'stalled':
        result = EXIT_STALLED
    elif reason == 'signal':
        result = 128 + stop['signal']
    elif status is not None:
        result = status
    elif args.status_file:
        log('the session ended without an exit status (killed from outside?)')
        result = EXIT_NO_STATUS
    else:
        result = 0
    log('session over (%s); exit status of the session %s'
        % (reason or 'ended by itself', status))
    return finish(result)


def spawn_root(path, command):
    """--spawn-root: the session wrapper runs claude through this inside the
    tmux pane. The command stays in this process group, so it keeps the
    terminal, but disclaims responsibility, so that macOS records it as the
    responsible process of what it starts. Its pid and start time go to
    path for the supervisor. Interrupts and SIGTERM sent to the pane's
    process group reach the command (its signals are defaulted) while this
    process ignores them and waits for its status."""
    if not command:
        print('deadline_run: no command after --', file=sys.stderr)
        return EXIT_USAGE
    try:
        child, disclaimed = spawn(command, dict(os.environ), new_session=False)
    except OSError as e:
        print('deadline_run: cannot start %s: %s' % (command[0], e),
              file=sys.stderr)
        return EXIT_CANNOT_START
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGQUIT):
        signal.signal(sig, signal.SIG_IGN)
    info = proc_info(child.pid)
    try:
        with open(path, 'w') as fh:
            fh.write('%d %d\n' % (child.pid, info.start if info else 0))
    except OSError as e:
        print('deadline_run: cannot write %s: %s' % (path, e), file=sys.stderr)
    child.wait()
    code = child.returncode
    return 128 - code if code < 0 else code


# Main.

def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if '--' in argv:
        split = argv.index('--')
        options, command = argv[:split], argv[split + 1:]
    else:
        options, command = argv, []
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--seconds', type=float)
    parser.add_argument('--until', help='also stop at the next local HH:MM')
    parser.add_argument('--grace', type=float, default=300,
                        help='seconds between SIGINT and SIGTERM')
    parser.add_argument('--term-grace', type=float, default=60,
                        help='seconds between SIGTERM and SIGKILL')
    parser.add_argument('--night-id',
                        help='value of %s for the command (default: new)'
                        % MARKER)
    parser.add_argument('--sweep-grace', type=float, default=10,
                        help='seconds between SIGTERM and SIGKILL in the '
                        'sweep')
    parser.add_argument('--show-deadline', action='store_true')
    parser.add_argument('--clean-stop-margin', type=float, default=2700)
    parser.add_argument('--now', help='the current time, for tests')
    parser.add_argument('--tz', help='the local time zone')
    parser.add_argument('--spawn-root', metavar='FILE',
                        help='run COMMAND disclaimed in this process group, '
                        'write "pid start" to FILE, exit with its status')
    parser.add_argument('--root-file',
                        help='tmux mode: the file the session wrapper\'s '
                        '--spawn-root writes')
    parser.add_argument('--tmux-socket', help='tmux mode: the server socket')
    parser.add_argument('--tmux-session', help='tmux mode: the session name')
    parser.add_argument('--tmux', default='tmux',
                        help='tmux mode: the tmux program')
    parser.add_argument('--status-file',
                        help='tmux mode: where the session writes its exit '
                        'status')
    parser.add_argument('--interrupt-wait', type=float, default=10,
                        help='tmux mode: seconds between Escape and /exit')
    parser.add_argument('--blocked-pattern',
                        help='tmux mode: a regular expression for a startup '
                        'dialog nobody will answer')
    parser.add_argument('--blocked-seconds', type=float, default=120,
                        help='tmux mode: how long after the start to look '
                        'for --blocked-pattern')
    parser.add_argument('--stall-seconds', type=float, default=0,
                        help='tmux mode: a failed start when, from the start, '
                        'the pane does not change and --transcript does not '
                        'grow for this long (0: never)')
    parser.add_argument('--transcript',
                        help='tmux mode: the session\'s transcript file, '
                        'whose growth shows that it has started')
    try:
        args = parser.parse_args(options)
    except SystemExit:
        return EXIT_USAGE
    if args.spawn_root:
        return spawn_root(args.spawn_root, command)
    if args.seconds is None:
        print('deadline_run: --seconds is required', file=sys.stderr)
        return EXIT_USAGE

    try:
        zone = local_zone(args.tz)
        now = parse_now(args.now, zone)
        limit = limit_seconds(args.seconds, args.until, now, zone)
    except ValueError as e:
        print('deadline_run: %s' % e, file=sys.stderr)
        return EXIT_USAGE

    if args.show_deadline:
        hard = now.astimezone(dt.timezone.utc) + dt.timedelta(seconds=limit)
        stop = min(stop_seconds(args), limit)
        stop_start = hard - dt.timedelta(seconds=stop)
        clean = hard - dt.timedelta(seconds=args.clean_stop_margin)
        print('limit_seconds=%d' % limit)
        print('stop_seconds=%d' % stop)
        print('hard=%s' % fmt(hard, zone))
        print('stop_start=%s' % fmt(stop_start, zone))
        print('clean_stop=%s' % fmt(clean, zone))
        return 0

    if not command:
        print('deadline_run: no command after --', file=sys.stderr)
        return EXIT_USAGE

    night_id = args.night_id or 'night-%s' % uuid.uuid4()
    env = dict(os.environ)
    env[MARKER] = night_id
    started = time.time()
    if bool(args.tmux_socket) != bool(args.tmux_session):
        print('deadline_run: --tmux-socket and --tmux-session go together',
              file=sys.stderr)
        return EXIT_USAGE
    if args.tmux_socket:
        return run_tmux(args, command, env, limit, night_id, started)
    try:
        child, disclaimed = spawn(command, env)
    except OSError as e:
        print('deadline_run: cannot start %s: %s' % (command[0], e),
              file=sys.stderr)
        return EXIT_CANNOT_START
    pgid = child.pid
    info = proc_info(child.pid)
    # The root's start time bounds the sweep; one second of slack covers
    # the difference between this clock reading and the kernel's.
    root_start = (info.start if info is not None
                  else int((started - 1) * 1000000))

    def forward(signum, frame):
        log('received signal %d; passing it to process group %d'
            % (signum, pgid))
        signal_group(pgid, signum)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, forward)

    log('started pid %d; limit %d seconds; %s=%s; responsibility %s'
        % (child.pid, limit, MARKER, night_id,
           'disclaimed' if disclaimed else 'NOT disclaimed (marker only)'))
    tracker = Tracker(child.pid, root_start, night_id)
    stop_polling = threading.Event()
    threading.Thread(target=poll, args=(tracker, stop_polling),
                     daemon=True).start()
    hit_deadline = not child.wait(limit)
    if hit_deadline:
        tracker.snapshot()
        log('deadline reached; sending SIGINT to process group %d' % pgid)
        signal_group(pgid, signal.SIGINT)
        if not child.wait(args.grace):
            tracker.snapshot()
            log('still running; sending SIGTERM')
            signal_group(pgid, signal.SIGTERM)
            if not child.wait(args.term_grace):
                tracker.snapshot()
                log('still running; sending SIGKILL')
                signal_group(pgid, signal.SIGKILL)
                child.wait()
    stop_polling.set()
    # Remember what is still in the group before it goes, so that what its
    # members started elsewhere is recognized in the sweep.
    tracker.snapshot()
    if signal_group(pgid, signal.SIGKILL):
        log('killed processes left in process group %d' % pgid)
    sweep(tracker, args.sweep_grace)

    if hit_deadline:
        return EXIT_DEADLINE
    code = child.returncode
    return 128 - code if code < 0 else code


if __name__ == '__main__':
    sys.exit(main())
