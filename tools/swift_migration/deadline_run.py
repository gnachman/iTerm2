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
alive), or the deadline.
When the session has ended is decided by EndWatch (its docstring has the
exact rule): the status file ends it at once; tmux's own answer that the
session or its server does not exist ends it only as a streak of at least
three such answers, none more than GONE_GAP (10) seconds after the last,
spanning --tmux-confirm-seconds (default 3), and, while the pane's first
process or the session root is still alive, spanning --tmux-doubt-seconds
(default 60); "no server running" or "error connecting" while the tmux
server process the run adopted is alive is not believed. A tmux call that
cannot be run, times out (--tmux-timeout, default 30) or fails any other
way is no answer at all; after --tmux-doubt-seconds with no answer that the
session is present, the tracked processes decide (none alive: over;
otherwise the session goes on, to the deadline at worst). The session root
dead for --tmux-doubt-seconds with no status file also ends it (125, with
its own log line). At the start the pane pid is asked for until it is
known, the stop sequence is due, or the session is confirmed gone by the
same rule (127). No tmux call runs past the start of the stop sequence, and
in the stop sequence and the cleanup none runs past the hard limit:
Escape, /exit and Enter take at most SEND_KEYS_TIMEOUT (10 seconds) out of
their step's own wait (sent once, never retried), and every other call at
most STOP_TMUX_TIMEOUT (1.5 seconds), so a hung tmux cannot delay the
signals that end the session and a slow one still gets /exit. A signal
stops the run at once, during the start too (after the tmux call in
progress, at most --tmux-timeout).
This replaces a rule under which any failed `tmux has-session` meant
"gone": on the first unattended night (2026-11-23), while the machine was
loaded by a sanitizer suite and a second build, the run was ended as if the
session had gone while it sat healthy at its prompt (the tmux server still
answered seven seconds later, and claude was still running when the stop
killed it); nothing logged which tmux call failed or how. Every failed tmux
call is now logged (arguments, exit status, stderr or exception; once per
distinct failure, then at most once a minute with a count), a failed
capture is no observation for the blocked and stall checks (never an empty
or unchanged screen), the final cleanup kills the server by pid when tmux
cannot be asked to, and an end without a status names what was observed.
The wrapper should keep the pane open after
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
ended by itself; 125 if it ended without one (killed from outside, or
tmux's server died; the log says what was observed); 124 at
the deadline; 122 if blocked; 121 if stalled at the start; 128 + the signal number if this runner was
signalled; 127 if it could not start.

Usage:
    deadline_run.py --seconds N [--until HH:MM] [--grace S] [--term-grace S]
                    [--night-id ID] [--sweep-grace S]
                    [--now ISO] [--tz ZONE] -- COMMAND [ARG...]
    deadline_run.py --seconds N ... --tmux-socket PATH --tmux-session NAME
                    [--tmux PROGRAM] [--status-file FILE]
                    [--interrupt-wait S] [--blocked-pattern REGEX]
                    [--blocked-seconds S] [--stall-seconds S]
                    [--transcript FILE] [--root-file FILE]
                    [--tmux-confirm-seconds S] [--tmux-doubt-seconds S]
                    [--tmux-timeout S] -- TMUX-CLIENT-COMMAND...
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

# What tmux 3.8 prints, with exit status 1, when what it was asked about
# does not exist (checked by hand): "can't find session: NAME" (the server
# runs, the session does not), "no server running on SOCKET" (the socket
# file is there but nothing listens: tmux prints this for ECONNREFUSED), and
# "error connecting to SOCKET (No such file or directory)" (no socket file).
# "session not found" is an older tmux's wording. Any other "error
# connecting to" errno, and every other message, is a failure to ask, not an
# answer. A refused connection can also be transient (a full listen backlog
# under load), which is one reason an answer must repeat before it counts.
GONE_MESSAGES = re.compile(
    r"^(can't find session|session not found|no server running on "
    r'|error connecting to .*\(No such file or directory\)$)')
ALIVE = 'alive'
GONE = 'gone'
UNKNOWN = 'unknown'

# A failure that has been logged is logged again, with its count, at most
# this often; distinct failures beyond MAX_FAILURE_KINDS share one entry
# per tmux command.
FAILURE_LOG_INTERVAL = 60
MAX_FAILURE_KINDS = 100
# The longest a tmux call outside the stop sequence's waits may take (the
# kill-server of the sequence; list-sessions and kill-server in the
# cleanup), and the existence checks inside them: STOP_SLACK's 10 seconds
# for tmux commands cover them. MIN_TMUX_TIMEOUT is the least any call is
# given.
STOP_TMUX_TIMEOUT = 1.5
MIN_TMUX_TIMEOUT = 0.2
# The longest Escape, /exit and Enter may take. They come out of their
# step's own wait, so a longer timeout cannot delay the SIGTERM; a tmux
# that is slow under load still gets them delivered. Each is sent once and
# never retried, since a call that timed out may have been delivered.
SEND_KEYS_TIMEOUT = 10
# The messages of GONE_MESSAGES that say no server runs: a contradiction
# while the server process the run adopted is alive.
NO_SERVER_MESSAGES = re.compile(r'^(no server running on |error connecting to )')


class Tmux:
    """tmux commands against one server socket and one session; never the
    default socket.

    Every call that does not succeed is logged with its arguments, its exit
    status, tmux's stderr or the exception, once per distinct failure and
    then at most once a minute with a count, so that a persistent failure
    cannot fill the log. A result's `asked` is true when the tmux client ran
    and exited by itself (not when it could not be run, timed out, or was
    killed by a signal); only then is its exit status an answer from tmux."""

    def __init__(self, program, socket, name, timeout=30,
                 clock=time.monotonic):
        self.program = program
        self.socket = socket
        self.name = name
        self.timeout = timeout
        self.clock = clock
        # A callable giving the longest any call may take now, or None:
        # run_tmux sets it so that no tmux call runs past the start of the
        # stop sequence, and in the stop sequence and the cleanup to
        # STOP_TMUX_TIMEOUT within the hard limit.
        self.cap = None
        self.calls = 0
        self.failed = 0
        self.failures = {}  # key -> {'count', 'logged_at', 'since'}

    def run(self, *args, timeout=None):
        """Run one tmux command, abandoned after the smallest of
        --tmux-timeout, `timeout` and the cap (never less than
        MIN_TMUX_TIMEOUT)."""
        self.calls += 1
        argv = [self.program, '-S', self.socket] + list(args)
        limit = self.timeout
        if timeout is not None:
            limit = min(limit, timeout)
        if self.cap is not None:
            limit = min(limit, self.cap())
        limit = max(limit, MIN_TMUX_TIMEOUT)
        try:
            got = subprocess.run(argv, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE,
                                 universal_newlines=True,
                                 timeout=limit)
            got.asked = got.returncode >= 0
            got.error = (None if got.asked
                         else 'killed by signal %d' % -got.returncode)
        except OSError as e:
            got = subprocess.CompletedProcess(argv, -1, '', '')
            got.asked = False
            got.error = 'cannot run %s: %s' % (self.program, e)
        except subprocess.TimeoutExpired:
            got = subprocess.CompletedProcess(argv, -1, '', '')
            got.asked = False
            got.error = 'timed out after %.1f seconds' % limit
        if got.returncode != 0:
            self.note_failure(args, got)
        return got

    def note_failure(self, args, got):
        self.failed += 1
        words = (got.stderr or '').strip()
        # A timeout's length varies with the cap; it is one kind of failure.
        kind = re.sub(r'[0-9.]+ seconds', 'N seconds', got.error or '')
        # Each key sent is its own kind, so that a failed /exit is not
        # hidden behind a failed Escape logged before it.
        what_kind = (' '.join(args) if args and args[0] == 'send-keys'
                     else args[0] if args else '')
        key = (what_kind, got.returncode, words, kind)
        if key not in self.failures and len(self.failures) >= MAX_FAILURE_KINDS:
            key = (key[0], 'other failures')
        now = self.clock()
        entry = self.failures.get(key)
        what = ' '.join([self.program, '-S', self.socket] + list(args))
        how = got.error or 'exit status %d' % got.returncode
        if entry is None:
            self.failures[key] = {'count': 1, 'logged_at': now, 'since': 0}
            log('tmux call failed: %s: %s; stderr %r' % (what, how, words))
            return
        entry['count'] += 1
        entry['since'] += 1
        if now - entry['logged_at'] >= FAILURE_LOG_INTERVAL:
            log('tmux call failed again (%d times since the last report, %d '
                'in all): %s: %s; stderr %r'
                % (entry['since'], entry['count'], what, how, words))
            entry['logged_at'] = now
            entry['since'] = 0

    def summary(self):
        return 'tmux: %d calls, %d failed' % (self.calls, self.failed)

    @staticmethod
    def classify(got):
        """ALIVE if tmux answered yes, GONE if it answered that the session
        or its server does not exist, UNKNOWN if it could not be asked or
        said anything else."""
        if got.returncode == 0:
            return ALIVE
        if (got.asked and got.returncode == 1
                and GONE_MESSAGES.search((got.stderr or '').strip())):
            return GONE
        return UNKNOWN

    def session_state(self, timeout=None):
        got = self.run('has-session', '-t', '=' + self.name, timeout=timeout)
        return self.classify(got), got

    def server_state(self, timeout=None):
        got = self.run('list-sessions', timeout=timeout)
        return self.classify(got), got

    def number(self, fmt):
        got = self.run('display-message', '-p', '-t', self.name, fmt)
        if got.returncode != 0:
            return None
        try:
            return int(got.stdout.strip())
        except ValueError:
            log('tmux display-message %s printed %r, not a number'
                % (fmt, got.stdout))
            return None

    def capture(self):
        """The pane's text, or None if it could not be captured: a failed
        capture is no observation, never an empty screen."""
        got = self.run('capture-pane', '-p', '-t', self.name)
        return got.stdout if got.returncode == 0 else None

    def send_keys(self, *keys, timeout=None):
        return self.run('send-keys', '-t', self.name, *keys,
                        timeout=timeout).returncode == 0

    def kill_server(self, timeout=None):
        return self.run('kill-server', timeout=timeout).returncode == 0


def read_status(path, settle=2.0):
    """The number in the status file, or None. A file that exists but does
    not hold a number yet (the wrapper's `echo` has created it and not yet
    written) is read again for up to `settle` seconds."""
    if not path:
        return None
    end = time.monotonic() + settle
    while True:
        try:
            with open(path) as fh:
                return int(fh.read().strip())
        except FileNotFoundError:
            return None
        except (OSError, ValueError):
            if time.monotonic() >= end:
                return None
        time.sleep(0.1)


# A "gone" answer from tmux counts only after this many answers in a row
# spanning --tmux-confirm-seconds.
CONFIRM_ANSWERS = 3
# Two gone answers further apart than this are not one streak: the second
# starts a new one. Ten check intervals of the main loop; a has-session
# call that takes longer than that under load is no evidence either way,
# and a streak with such holes is not "sustained".
GONE_GAP = 10
# How often the fallback's "the session goes on" line is repeated.
FALLBACK_LOG_INTERVAL = 300
# How session_processes() names the session root (claude, through
# --spawn-root) and the pane's first process (session.sh).
SESSION_ROOT = 'the session root'
PANE_FIRST = "the pane's first process"


def tracked_alive(tracked):
    """[(pid, start, what)] to [(pid, what, alive)]: alive while the pid is
    still the process that was seen (same start time, not a zombie), so a
    reused pid does not count."""
    result = []
    for pid, start, what in tracked:
        now = proc_info(pid)
        result.append((pid, what, now is not None and now.start == start
                       and now.status != SZOMB))
    return result


class EndWatch:
    """Decides whether the session has ended. The first night of the
    unattended run (2026-11-23) was ended by a single failed `tmux
    has-session` while the session sat healthy at its prompt, because "the
    tmux client failed" was read as "the session is gone".

    Each check asks `tmux has-session` once (about once a second in the main
    loop, five times a second in the stop sequence) and gets one of three
    results: present (exit 0), gone (exit 1 with one of GONE_MESSAGES from a
    client that ran and exited by itself), or a failure to ask (anything
    else: the client could not be run, timed out, was killed, or said
    something else). A "no server running on" or "error connecting to"
    answer while the tmux server process that the run adopted (same pid and
    start time) is alive contradicts itself (a refused connection under
    load, a deleted socket file) and counts as a failure to ask, logged.
    "Tracked processes" are the pane's first process and the session root,
    each while it is the process that was seen.

    The rule; once it has concluded, it stays concluded:
      1. The status file exists: over.
      2. The session root has exited, no status file has appeared, and that
         has lasted `doubt` seconds: over, whatever tmux says (claude is
         gone; the wrapper could not write the status). Logged once when
         first seen after `confirm` seconds.
      3. Present: not over; the gone streak ends.
      4. Gone answers form a streak: each within GONE_GAP seconds of the
         previous one, with no present answer between (failures to ask
         between them neither count nor break it, but a gap longer than
         GONE_GAP starts a new streak). The streak ends the session when it
         has at least CONFIRM_ANSWERS answers spanning at least `confirm`
         seconds and either no tracked process is alive (or none is
         tracked), or it spans at least `doubt` seconds (a session whose
         tmux is truly gone has lost its terminal, so its processes
         normally die of the hangup at once; tmux that is truly gone
         answers at once, every time).
      5. No present answer for `doubt` seconds (from the last present
         answer, or from the start of watching): the tracked processes
         decide. None alive: over. Any alive, or none tracked: the session
         goes on, to the deadline at worst, logged every
         FALLBACK_LOG_INTERVAL seconds.
    So live tracked processes are killed on tmux's word only by rule 4's
    sustained streak, and on the session root's death only by rule 2.

    `session_processes()` returns [(pid, what, alive)] or None when nothing
    is tracked; `server_running()` returns True, False, or None when the
    server process is not tracked."""

    def __init__(self, tmux, status_file, confirm, doubt, session_processes,
                 clock=time.monotonic, server_running=None):
        self.tmux = tmux
        self.status_file = status_file
        self.confirm = confirm
        self.doubt = doubt
        self.session_processes = session_processes
        self.server_running = server_running or (lambda: None)
        self.clock = clock
        self.over = None  # why, once concluded
        self.last_state = None
        self.last_present = clock()
        self.root_dead_since = None
        self.root_logged = False
        self.contradiction_logged = False
        self.fallback_logged_at = None
        self.unanswered = 0
        self.gone_answers = 0
        self.last_failure = ''
        self.end_streak()
        self.doubt_logged = False

    def end_streak(self):
        self.gone_first = None
        self.gone_last = None
        self.gone_count = 0
        self.gone_words = ''

    def conclude(self, why):
        self.over = why
        log('the session is over: %s' % why)
        return True

    @staticmethod
    def describe(processes):
        return ', '.join('pid %d (%s)' % (pid, what)
                         for pid, what, _ in processes)

    def look(self):
        """(tracked, running): the tracked processes, or None, and those
        of them still alive."""
        tracked = self.session_processes()
        if tracked is None:
            return None, None
        return tracked, [p for p in tracked if p[2]]

    def check_root(self, now, tracked):
        # Rule 2.
        root = [p for p in tracked or [] if p[1] == SESSION_ROOT]
        if not root or root[0][2]:
            self.root_dead_since = None
            return False
        if self.root_dead_since is None:
            self.root_dead_since = now
        dead_for = now - self.root_dead_since
        if dead_for >= self.doubt:
            return self.conclude(
                'the session root, pid %d, exited at least %.0f seconds ago '
                'and no status file was written (%s); the pane goes on '
                'without it' % (root[0][0], dead_for, self.status_file))
        if dead_for >= self.confirm and not self.root_logged:
            log('the session root, pid %d, has exited and no status file '
                'has appeared; the run ends if none appears within %g '
                'seconds' % (root[0][0], self.doubt))
            self.root_logged = True
        return False

    def check(self, timeout=None):
        if self.over is not None:
            return True
        if self.status_file and os.path.exists(self.status_file):
            self.over = 'the status file %s appeared' % self.status_file
            return True
        state, got = self.tmux.session_state(timeout=timeout)
        now = self.clock()
        words = (got.stderr or '').strip()
        if (state == GONE and NO_SERVER_MESSAGES.search(words)
                and self.server_running() is True):
            if not self.contradiction_logged:
                log('tmux says %r, but the tmux server process (server pid '
                    'tracked since the start) is alive; not believed, '
                    'counted as a failure to ask' % words)
                self.contradiction_logged = True
            state = UNKNOWN
        self.last_state = state
        tracked, running = self.look()
        if self.status_file and self.check_root(now, tracked):
            return True
        if state == ALIVE:
            if self.doubt_logged:
                log('tmux answers again that session %s is present; the '
                    'session goes on' % self.tmux.name)
                self.doubt_logged = False
            self.end_streak()
            self.last_present = now
            self.unanswered = 0
            self.gone_answers = 0
            self.contradiction_logged = False
            return False
        if state == GONE:
            self.gone_answers += 1
            if self.gone_last is not None and now - self.gone_last > GONE_GAP:
                self.end_streak()
            if self.gone_first is None:
                self.gone_first = now
            self.gone_last = now
            self.gone_count += 1
            self.gone_words = words
            span = now - self.gone_first
            if self.gone_count >= CONFIRM_ANSWERS and span >= self.confirm:
                what = ('tmux answered %d times over %.1f seconds, never more '
                        'than %g seconds apart (has-session -t =%s, exit '
                        'status 1), that the session is gone, in its words: '
                        '%r' % (self.gone_count, span, GONE_GAP,
                                self.tmux.name, self.gone_words))
                if tracked is None:
                    return self.conclude(what + '; no process of the session '
                                         'is tracked to say otherwise')
                if not running:
                    return self.conclude(what + '; the tracked processes are '
                                         'gone too: %s'
                                         % self.describe(tracked))
                if span >= self.doubt:
                    return self.conclude(
                        what + '; these still run after %g seconds of such '
                        'answers and are killed with the rest: %s'
                        % (self.doubt, self.describe(running)))
                if not self.doubt_logged:
                    log('%s; but these still run: %s; not believed unless '
                        'such answers last %g seconds'
                        % (what, self.describe(running), self.doubt))
                    self.doubt_logged = True
        else:
            self.unanswered += 1
            self.last_failure = '%s; stderr %r' % (
                got.error or 'exit status %d' % got.returncode, words)
        # Rule 5.
        silent = now - self.last_present
        if silent < self.doubt:
            return False
        what = ('could not ask tmux whether session %s is present: no '
                'present answer for %.0f seconds (%d gone answers, %d '
                'failures to ask; the last failure: %s)'
                % (self.tmux.name, silent, self.gone_answers,
                   self.unanswered, self.last_failure or 'none'))
        if tracked is not None and not running:
            return self.conclude(what + '; the tracked processes are gone, '
                                 'so the session is over: %s'
                                 % self.describe(tracked))
        if (self.fallback_logged_at is None
                or now - self.fallback_logged_at >= FALLBACK_LOG_INTERVAL):
            if tracked is None:
                log(what + '; no process of the session is tracked, so '
                    'nothing decides: the session goes on until the deadline')
            else:
                log(what + '; these still run, so the session goes on: %s'
                    % self.describe(running))
            self.fallback_logged_at = now
            self.doubt_logged = True
        return False


def run_tmux(args, command, env, limit, night_id, started):
    tmux = Tmux(args.tmux, args.tmux_socket, args.tmux_session,
                timeout=args.tmux_timeout)
    stop = {'signal': None}

    def on_signal(signum, frame):
        log('received signal %d; stopping the session' % signum)
        stop['signal'] = signum

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, on_signal)

    def ask(question, tries=6, pause=0.5):
        # At the start: ask again while tmux cannot be asked, a few times.
        for attempt in range(tries):
            got = question()
            if got is not None and got != UNKNOWN:
                return got
            if attempt + 1 < tries:
                time.sleep(pause)
        return got

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
    # The stop sequence starts early enough to be over by the hard limit.
    # Both are counted from here, the end of the start; no tmux call before
    # the stop sequence may run past its start.
    stop_len = stop_seconds(args)
    hard = Deadline(limit)
    deadline = Deadline(max(0.0, limit - stop_len))
    tmux.cap = lambda: max(MIN_TMUX_TIMEOUT, deadline.remaining())
    pane_pid = server_pid = None
    pane_info = server_info = None
    adopted = {'root': False, 'pid': None, 'start': None}

    def session_processes():
        # The processes whose life says whether the session runs: the
        # pane's first process and the session root, each while it is still
        # the process that was seen. None when neither is tracked.
        tracked = []
        if pane_info is not None:
            tracked.append((pane_pid, pane_info.start, PANE_FIRST))
        if adopted['pid'] is not None:
            tracked.append((adopted['pid'], adopted['start'], SESSION_ROOT))
        return tracked_alive(tracked) if tracked else None

    def server_running():
        # Whether the tmux server process adopted at the start is alive;
        # None while it is not known.
        if server_info is None:
            return None
        return tracked_alive([(server_pid, server_info.start, 'server')])[0][2]

    watch = EndWatch(tmux, args.status_file, args.tmux_confirm_seconds,
                     args.tmux_doubt_seconds, session_processes,
                     server_running=server_running)
    ended = watch.check
    stop_polling = threading.Event()
    threading.Thread(target=poll, args=(tracker, stop_polling),
                     daemon=True).start()

    if code == 0:
        # Learn the pane's first process. A failure to ask is no
        # information: keep asking while the session is present or tmux
        # cannot be asked, until the stop sequence is due. Only the watch's
        # confirmed end (the status file, or tmux's sustained answer that
        # the session is gone) stops this early.
        asked_from = time.monotonic()
        while not ended():
            if stop['signal'] is not None:
                # The main loop below stops on it at once; the pane pid
                # may stay unknown (then only the sweep and tmux's own
                # kill-server can reach the pane).
                log('a signal arrived during the start; stopping')
                break
            if watch.last_state == ALIVE:
                pane_pid = tmux.number('#{pane_pid}')
                if pane_pid:
                    break
            if deadline.remaining() <= 0:
                log('could not learn the pane pid before the stop sequence '
                    'was due')
                break
            time.sleep(0.5)
        if pane_pid:
            if time.monotonic() - asked_from > 2:
                log('learned the pane pid after %.0f seconds'
                    % (time.monotonic() - asked_from))
            server_pid = ask(lambda: tmux.number('#{pid}'), tries=10)
            for pid, what in ((server_pid, 'the tmux server'),
                              (pane_pid, PANE_FIRST)):
                if pid:
                    tracker.adopt(pid, what)
            pane_info = proc_info(pane_pid)
            server_info = proc_info(server_pid) if server_pid else None
    log('tmux client pid %d exited %s; session %s on %s; server pid %s; '
        'pane pid %s; %s=%s; responsibility %s'
        % (client.pid, code, args.tmux_session, args.tmux_socket, server_pid,
           pane_pid, MARKER, night_id,
           'disclaimed' if disclaimed else 'NOT disclaimed (marker only)'))

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
                adopted['pid'] = pid
                adopted['start'] = start
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
        stop_polling.set()
        adopt_root()
        tracker.snapshot()
        stop_caps()
        # Unless tmux answered that no server runs, ask it to stop; if it
        # cannot be asked, the server is killed by pid below.
        server_state, _ = tmux.server_state(timeout=STOP_TMUX_TIMEOUT)
        if server_state != GONE:
            if tmux.kill_server(timeout=STOP_TMUX_TIMEOUT):
                log('killed the tmux server on %s' % args.tmux_socket)
            else:
                log('could not ask tmux to kill its server on %s (it '
                    'answered %s to list-sessions); %s'
                    % (args.tmux_socket, server_state,
                       'killing it by pid %d' % server_pid if server_pid
                       else 'its pid is not known, so only the sweep can '
                       'reach it'))
        log(tmux.summary())
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

    def stop_caps():
        # From the stop sequence on, no tmux call runs past the hard limit;
        # each call also gets its own short timeout (STOP_TMUX_TIMEOUT, or
        # SEND_KEYS_TIMEOUT out of its step's wait), so the signals that end
        # the session, which need no tmux, come on time.
        tmux.cap = lambda: max(MIN_TMUX_TIMEOUT, hard.remaining())

    if code != 0:
        log('the session could not be started (tmux client exit %s)' % code)
        return finish(EXIT_CANNOT_START)
    if pane_pid is None and watch.over is not None and not (
            args.status_file and os.path.exists(args.status_file)):
        log('the session could not be started: %s' % watch.over)
        return finish(EXIT_CANNOT_START)

    zone = dt.datetime.now().astimezone().tzinfo
    log('hard limit %s; the stop sequence starts at %s (%d seconds before, '
        'the longest it can take)'
        % (fmt(dt.datetime.fromtimestamp(hard.at, zone), zone),
           fmt(dt.datetime.fromtimestamp(deadline.at, zone), zone), stop_len))
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
        if screen is None:
            # A failed capture is no observation: it neither changes the
            # screen nor counts as unchanged. A stall is two successful
            # captures that agree, --stall-seconds apart.
            return False
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
            screen = tmux.capture()
            match = pattern.search(screen) if screen is not None else None
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

    def left(end):
        return max(MIN_TMUX_TIMEOUT, end - time.monotonic())

    def wait_end(end):
        # Until the monotonic time `end`; each check's tmux call gets no
        # more than what is left, so the wait does not overrun.
        while time.monotonic() < end:
            if ended(timeout=min(STOP_TMUX_TIMEOUT, left(end))):
                return True
            time.sleep(0.2)
        return ended(timeout=MIN_TMUX_TIMEOUT)

    if reason is not None:
        stop_caps()
        tracker.snapshot()
        log('%s; sending Escape to the session'
            % {'deadline': 'the stop sequence starts (deadline)',
               'signal': 'stopping on a signal',
               'blocked': 'blocked at startup',
               'stalled': 'failed start'}[reason])
        # Each step's tmux calls come out of its own wait, so a hung tmux
        # cannot push the SIGTERM and the SIGKILL later.
        step_end = time.monotonic() + args.interrupt_wait
        tmux.send_keys('Escape',
                       timeout=min(SEND_KEYS_TIMEOUT, left(step_end)))
        if not wait_end(step_end):
            log('typing /exit')
            step_end = time.monotonic() + args.grace
            tmux.send_keys('-l', '/exit',
                           timeout=min(SEND_KEYS_TIMEOUT, left(step_end)))
            tmux.send_keys('Enter',
                           timeout=min(SEND_KEYS_TIMEOUT, left(step_end)))
            if not wait_end(step_end):
                tracker.snapshot()
                log("still running; sending SIGTERM to the pane's process "
                    'group %s' % pane_pid)
                members = signal_pane(signal.SIGTERM, 'SIGTERM')
                ok = wait_end(time.monotonic() + args.term_grace)
                report_pane(members, 'SIGTERM')
                if not ok:
                    tracker.snapshot()
                    log('still running; killing the tmux server')
                    tmux.kill_server(timeout=STOP_TMUX_TIMEOUT)
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
        log('the session ended without an exit status (killed from '
            'outside?); what was observed: %s' % watch.over)
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
    parser.add_argument('--tmux-confirm-seconds', type=float, default=3,
                        help='tmux mode: how long tmux\'s answer that the '
                        'session is gone must repeat before it counts')
    parser.add_argument('--tmux-doubt-seconds', type=float, default=60,
                        help='tmux mode: how long tmux may claim the session '
                        'gone while its processes run, or be impossible to '
                        'ask, before those processes decide')
    parser.add_argument('--tmux-timeout', type=float, default=30,
                        help='tmux mode: seconds before a tmux call is '
                        'abandoned')
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
