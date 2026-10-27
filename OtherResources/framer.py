#!/usr/bin/env python3
import asyncio
import atexit
import base64
import contextlib
import errno
import fcntl
import json
import os
import platform
import pty
import pwd
import random
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import textwrap
import threading
import time
import traceback
import zipfile

# pid -> Process
PROCESSES = {}
# %output channel for a pane process (see handle_pane). iTerm2 hands its bytes to the session
# that owns the pane rather than parsing them as the login shell's output or as a command's.
PANE_CHANNEL = 3
# List of pids that are completed. Their tasks can be awaited and removed.
COMPLETED = []
VERBOSE=0
LOGFILE=None
RUNLOOP=None
TASKS=[]
QUITTING=False
# Identifiers whose reply has been ended, so handle() can tell whether a handler that raised
# still owes one.
REPLIED=set()
REGISTERED=[]
LASTPS={}
AUTOPOLL = 0
AUTOPOLL_TASK = None
TTY_TASK = None
RECOVERY_STATE={}
#{SUB}
BASEID=str(random.randint(0, 1048576)) + str(os.getpid()) + str(int(time.time() * 1000000))
IDCOUNT=0
SEARCH_TASK = None
# it2-over-ssh: the unix-socket server the remote `it2` connects to, and the
# accepted connections (connid -> asyncio StreamWriter). Dormant until iTerm2
# sends the "it2listen" command.
IT2_SERVER = None
IT2_CONNS = {}
# connids whose close iTerm2 initiated via it2close. The reader coroutine checks this in its
# finally so it does NOT echo a duplicate `%it2 close` back for a connid iTerm2 already tore
# down. A framer/client-initiated teardown (client disconnect, buffer-cap abort) is NOT in
# here, so it still emits close to inform iTerm2. Each entry is discarded by the reader.
IT2_LOCALLY_CLOSED = set()
# Path of the bound it2 socket, remembered so we can unlink it on shutdown (it
# lives in a persistent, per-user directory, so a leaked socket would linger).
IT2_SOCKET_PATH = None
# Liveness lock for the bound socket: a live framer holds an exclusive advisory flock on
# a sidecar "<socket>.lock" file for its entire lifetime. The kernel releases that lock
# when the process dies (including SIGKILL when an ssh connection drops), so another
# framer can tell a leaked socket from a live one by whether its lock is acquirable,
# with no timing race and without connecting to the socket. IT2_LOCK_FD is kept open the
# whole time precisely to hold the lock; IT2_LOCK_PATH is its file, unlinked on teardown.
IT2_LOCK_FD = None
IT2_LOCK_PATH = None
# For a home too long for a socket path, iTerm2 puts the socket in a fresh /tmp/.it2-<hex>
# directory instead of ~/.iterm2/it2 (Conductor.it2SocketPath). That directory is this
# connection's alone, so it goes when the socket does; IT2_SOCKET_TMPDIR names it.
IT2_TMP_SOCKET_ROOT = "/tmp"
IT2_TMP_SOCKET_PREFIX = ".it2-"
IT2_SOCKET_TMPDIR = None
# How old an empty /tmp/.it2-* directory must be before a sweep removes it, so one another
# framer has just made, and not yet locked, is left alone.
IT2_TMP_SOCKET_DIR_GRACE = 60
# Upper bound on a single it2 client's unsent (buffered) bytes. it2send writes without
# awaiting drain() -- draining on the shared command loop would let a stalled consumer's
# backpressure freeze send/kill/file/poll for the whole SSH session -- so instead we bound
# memory: a stalled consumer whose buffer grows past this is dropped, not the loop.
IT2_WRITE_BUFFER_MAX = 4 * 1024 * 1024  # 4 MiB
# framer emits one OSC 134 "%it2 <connid> data <b64>" frame per socket read (via
# send_esc), and iTerm2's conductor OSC parser accumulates a frame's payload one
# char at a time (O(n^2) in its length). Normal up-traffic is only tiny
# HELLO/CANCEL, so this cap is inert in practice; it just stops a misbehaving or
# hostile client on the socket from feeding one giant frame to that parser. The
# demux reassembles the it2.py wire frames across chunks.
IT2_READ_CHUNK = 1024

def squash(i):
    a = list(map(chr, list(range(48,58))+list(range(65,91))+list(range(97,123))))
    b = len(a)
    return a[i] if i < b else squash(i // b) + a[i % b]

def makeid():
    global IDCOUNT
    result = BASEID + str(IDCOUNT)
    IDCOUNT += 1
    return squash(int(result))

def log(message):
    pass

def send(q, data):
    if QUITTING:
        log("[squelched] " + str(data))
        return
    log("> " + str(data))
    q.append(data)

def send_esc(q, text):
    if QUITTING:
        log("[squelched] " + str(text))
        return
    log("> [osc 134] " + str(text) + " [st]")
    q.append('\033]134;:' + str(text) + '\033\\')

def lock():
    return []

def _write_all(fd, data):
    # os.write can write FEWER bytes than requested (a signal such as SIGWINCH delivered after
    # a partial write, or a full pipe). PEP 475 only auto-retries on EINTR when zero bytes were
    # written, so a partial write is NOT retried -- loop until every byte is out. Dropping the
    # tail here silently truncates an up-channel OSC frame and desyncs iTerm2's conductor
    # parser for the whole ssh session, not just one it2 command.
    if isinstance(data, str):
        data = data.encode('utf-8')
    view = memoryview(data)
    total = 0
    length = len(view)
    while total < length:
        try:
            written = os.write(fd, view[total:])
        except InterruptedError:
            continue  # EINTR with no progress: retry
        if written <= 0:
            break  # fd closed / unwritable; give up rather than spin
        total += written


def unlock(writes):
    if writes:
        for data in writes:
            _write_all(sys.stdout.fileno(), data)
        sys.stdout.flush()

## Flow control, version 1
#
# iTerm2 grants credit in bytes and the framer reads its programs' output only while it has
# some, so a backlog waits in the remote pty, where Ctrl-C discards it, instead of in sshd's
# and TCP's buffers, where it cannot be recalled. iTerm2 sizes the credit from one-way delay
# measured with the timestamps on %output frames. Off until iTerm2 sends `flow on`; until then
# the framer reads and frames output exactly as before.

# The newest version this framer speaks. iTerm2 asks for one with `flow on [version]`.
# Version 1 has a single flow; version 2 gives the leader, each pane and it2 credit of their own.
FLOW_VERSION = 2
FLOW_READ_SIZE = 4096
FLOW_INITIAL_CREDIT = 8192
# A drain with no grant for this long ends itself, so a controller that dies mid-drain cannot
# freeze the session.
FLOW_DRAIN_TIMEOUT = 10.0
FLOW_DRAIN_FLOOR = 2048
# The safety valve: no grant of any kind (heartbeats included) for this long while commands
# still arrive means the controller is dead but iTerm2 is not, so trickle output.
FLOW_VALVE_SILENCE = 5.0
FLOW_VALVE_RATE = 4096
# The login shell may send small writes (echo, a prompt) outside credit, so they are not held
# behind a side command that has used the credit up.
FLOW_ECHO_ALLOWANCE = 256
FLOW_ECHO_REFILL = 2560
FLOW_TICK = 0.25
FLOW_FLAG_LIMITED = 1
FLOW_FLAG_EXEMPT = 2
# Flows. A pane's flow is its pid.
FLOW_LEADER = 'leader'
FLOW_IT2 = 'it2'

def _flow_clock():
    """A clock that never jumps and counts time asleep, so its offset from iTerm2's stays put."""
    if hasattr(time, 'CLOCK_BOOTTIME'):
        return 'boottime', time.CLOCK_BOOTTIME
    if platform.system() == 'Darwin':
        # Counts sleep on macOS, unlike time.monotonic(), which uses mach_absolute_time().
        return 'monotonic', time.CLOCK_MONOTONIC
    return 'uptime', None

FLOW_CLOCK_NAME, FLOW_CLOCK_ID = _flow_clock()

def flow_clock_name():
    return FLOW_CLOCK_NAME

def _flow_ns():
    if FLOW_CLOCK_ID is None:
        return time.monotonic_ns()
    return time.clock_gettime_ns(FLOW_CLOCK_ID)

def flow_now():
    return _flow_ns() / 1e9

def flow_send_ms():
    return _flow_ns() // 1000000

class FlowControl:
    """The framer's side of flow control: credit, drains, the valve and the echo allowance.
    Takes its clock so tests can run it on fake time.

    Credit belongs to a flow: FLOW_LEADER (the login shell and side commands), a pane's pid, or
    FLOW_IT2. In version 1 every source spends the leader's credit and it2 data is not
    controlled; in version 2 each flow has credit of its own, granted separately, so a peer
    whose session reads slowly holds back only itself."""

    def __init__(self, clock):
        self.clock = clock
        self.enabled = False
        self.version = 0
        self.credits = {}
        # Flows that ran out of credit since their last frame.
        self.limited_flows = set()
        self.draining = False
        self.drain_started = 0
        self.valve_open = False
        self.valve_at = 0
        self.last_grant = 0
        # When output last started waiting for credit, or None while nothing waits.
        self.waiting_since = None
        self.last_command = None
        self.bucket = 0
        self.bucket_at = 0

    def enable(self, version=1):
        now = self.clock()
        self.enabled = True
        self.version = version
        # The leader starts with the initial credit; iTerm2 grants other flows theirs.
        self.credits = {FLOW_LEADER: FLOW_INITIAL_CREDIT}
        self.limited_flows = set()
        self.draining = False
        self.valve_open = False
        self.last_grant = now
        self.bucket = FLOW_ECHO_ALLOWANCE
        self.bucket_at = now

    def disable(self):
        self.enabled = False
        self.draining = False
        self.valve_open = False

    def _key(self, flow):
        return flow if self.version >= 2 else FLOW_LEADER

    def controls(self, flow):
        """Whether reading from `flow` needs credit."""
        return self.enabled and (self.version >= 2 or flow != FLOW_IT2)

    @property
    def credit(self):
        """The leader's credit."""
        return self.credits.get(FLOW_LEADER, 0)

    def credit_of(self, flow):
        return self.credits.get(self._key(flow), 0)

    def budget(self, flow=FLOW_LEADER):
        """How many bytes may be read from a source of `flow` now."""
        if not self.controls(flow):
            return FLOW_READ_SIZE
        return max(0, min(self.credit_of(flow), FLOW_READ_SIZE))

    def has_credit(self):
        return not self.enabled or any(c > 0 for c in self.credits.values())

    def spend(self, n, flow=FLOW_LEADER):
        if not self.controls(flow):
            return
        key = self._key(flow)
        credit = self.credits.get(key, 0) - n
        if credit <= 0:
            credit = 0
            self.limited_flows.add(key)
        self.credits[key] = credit

    def take_flags(self, exempt=False, flow=FLOW_LEADER):
        """Flags for the flow's frame about to be sent. LIMITED marks the frame that used up the
        flow's credit, which tells iTerm2 its rate samples were limited by the window."""
        key = self._key(flow)
        flags = FLOW_FLAG_LIMITED if key in self.limited_flows else 0
        self.limited_flows.discard(key)
        if exempt:
            flags |= FLOW_FLAG_EXEMPT
        return flags

    def grant(self, n, flow=FLOW_LEADER):
        if not self.enabled:
            return
        key = self._key(flow)
        self.credits[key] = self.credits.get(key, 0) + n
        self.last_grant = self.clock()
        self.draining = False
        self.valve_open = False

    def forget(self, flow):
        """A pane ended; its credit goes with it."""
        if self.version >= 2 and flow != FLOW_LEADER:
            self.credits.pop(flow, None)
            self.limited_flows.discard(flow)

    def drain(self):
        if not self.enabled:
            return
        for key in self.credits:
            self.credits[key] = 0
        self.draining = True
        self.drain_started = self.clock()
        self.valve_open = False

    def recover(self):
        """A new iTerm2 attached. Keep flow control on with no credit: everything sent before
        the recovery block is backlog, and iTerm2 grants afresh once it has read it."""
        if self.enabled:
            self.drain()

    def note_command(self):
        self.last_command = self.clock()

    def _refill(self):
        now = self.clock()
        self.bucket = min(FLOW_ECHO_ALLOWANCE,
                          self.bucket + (now - self.bucket_at) * FLOW_ECHO_REFILL)
        self.bucket_at = now

    def take_echo_allowance(self, waiting):
        """Whether the login shell may send `waiting` bytes outside credit. A flood never
        qualifies: it always has more than the allowance waiting."""
        if not self.enabled or waiting <= 0 or waiting > FLOW_ECHO_ALLOWANCE:
            return False
        self._refill()
        if self.bucket < waiting:
            return False
        self.bucket -= waiting
        return True

    def echo_allowance_delay(self, waiting):
        """Seconds until take_echo_allowance(waiting) could succeed."""
        self._refill()
        return max(0.0, (waiting - self.bucket) / FLOW_ECHO_REFILL)

    def tick(self, waiting):
        """Called every FLOW_TICK. `waiting` is the set of flows with output held for lack of
        credit (True means the leader's). Returns True when the valve opens, so the caller can
        report it."""
        if not self.enabled:
            return False
        if waiting is True:
            waiting = {FLOW_LEADER}
        elif not waiting:
            waiting = set()
        waiting = {self._key(flow) for flow in waiting}
        now = self.clock()
        if self.draining:
            if now - self.drain_started >= FLOW_DRAIN_TIMEOUT:
                self.draining = False
                for key in self.credits:
                    self.credits[key] = max(self.credits[key], FLOW_DRAIN_FLOOR)
            return False
        if self.valve_open:
            bytes_due = int((now - self.valve_at) * FLOW_VALVE_RATE)
            self._add_to(waiting, bytes_due)
            self.valve_at += bytes_due / FLOW_VALVE_RATE
            return False
        if not waiting:
            self.waiting_since = None
            return False
        if self.waiting_since is None:
            self.waiting_since = now
        # Silence counts from when output began waiting: an idle iTerm2 has no reason to
        # grant, so the last grant can be long past when a flood starts.
        silence = now - max(self.last_grant, self.waiting_since)
        if (silence >= FLOW_VALVE_SILENCE and
                self.last_command is not None and now - self.last_command < FLOW_VALVE_SILENCE):
            self.valve_open = True
            self.valve_at = now
            self._add_to(waiting, int(FLOW_VALVE_RATE * FLOW_TICK))
            return True
        return False

    def _add_to(self, flows, n):
        """The valve's trickle, shared by the flows that are waiting."""
        if not flows:
            flows = {FLOW_LEADER}
        share = n // len(flows)
        for key in flows:
            self.credits[key] = self.credits.get(key, 0) + share

FLOW = FlowControl(flow_now)

class FlowSource:
    """A program's pty, read through the pump so that reads respect credit."""

    def __init__(self, fd, callback, channel, proc):
        self.fd = fd
        self.callback = callback
        self.channel = channel
        self.proc = proc
        self.watching = False
        # Readable but not yet read: waiting for the pump, or for credit.
        self.ready = False
        # Up to FLOW_ECHO_ALLOWANCE + 1 bytes read while there was no credit, held until there
        # is. Reading them tells end of output apart from data, and echo from a flood, without
        # FIONREAD, which reports 0 for a pty master on macOS.
        self.pending = None
        self.closed = False

    @property
    def is_login(self):
        return self.proc is not None and self.proc.login

    @property
    def flow(self):
        """Whose credit reads from this source spend."""
        if self.proc is not None and self.proc.pane:
            return self.proc.pid
        return FLOW_LEADER

    @property
    def blocked(self):
        return self.ready and not self.closed

# Every program's pty, in the order the pump serves them.
SOURCES = []
PUMP_SCHEDULED = False
PUMP_ROTATION = 0
PUMP_TASKS = set()
FLOW_TICK_HANDLE = None
ECHO_TIMER = None
IT2_GATE = None

def add_source(source):
    os.set_blocking(source.fd, False)
    SOURCES.append(source)
    _watch(source)

def remove_source(source):
    _unwatch(source)
    source.closed = True
    source.ready = False
    if source in SOURCES:
        SOURCES.remove(source)

def _watch(source):
    if source.watching or source.closed:
        return
    asyncio.get_event_loop().add_reader(source.fd, _on_readable, source)
    source.watching = True

def _unwatch(source):
    if not source.watching:
        return
    with contextlib.suppress(Exception):
        asyncio.get_event_loop().remove_reader(source.fd)
    source.watching = False

def _on_readable(source):
    # Stop watching until the pump has read it; a source held for lack of credit would
    # otherwise wake the loop continuously.
    _unwatch(source)
    source.ready = True
    _schedule_pump()

def _schedule_pump():
    global PUMP_SCHEDULED
    if PUMP_SCHEDULED:
        return
    PUMP_SCHEDULED = True
    asyncio.get_event_loop().call_soon(pump_sources)

def pump_sources():
    """Read once from each ready source, round-robin, as far as credit allows. Sources that
    cannot be read stay ready (held) until a grant or the valve adds credit."""
    global PUMP_SCHEDULED, PUMP_ROTATION
    PUMP_SCHEDULED = False
    ready = [s for s in SOURCES if s.ready and not s.closed]
    if not ready:
        return
    start = PUMP_ROTATION % len(ready)
    PUMP_ROTATION += 1
    for source in ready[start:] + ready[:start]:
        _service(source)

def _read(source, size):
    try:
        return os.read(source.fd, size)
    except BlockingIOError:
        return None
    except OSError:
        # EIO: the pty's other end is closed.
        return b''

def _service(source):
    flow = source.flow
    budget = FLOW.budget(flow)
    exempt = False
    if budget == 0:
        if source.pending is None:
            peeked = _read(source, FLOW_ECHO_ALLOWANCE + 1)
            if peeked is None:
                _wait_for_more(source)
                return
            if peeked:
                source.pending = peeked
        if source.pending is None:
            # End of output costs no credit, so the program's exit is reported at once.
            data = b''
        elif source.is_login and FLOW.take_echo_allowance(len(source.pending)):
            data = source.pending
            source.pending = None
            exempt = True
        else:
            if source.is_login and len(source.pending) <= FLOW_ECHO_ALLOWANCE:
                _retry_echo_after(FLOW.echo_allowance_delay(len(source.pending)))
            return
    elif source.pending is not None:
        data = source.pending[:budget]
        source.pending = source.pending[budget:] or None
    else:
        data = _read(source, budget)
        if data is None:
            _wait_for_more(source)
            return
    if source.pending is None:
        source.ready = False
    if not exempt:
        FLOW.spend(len(data), flow)
    result = source.callback(source.channel, data, exempt)
    if not data:
        remove_source(source)
    elif not source.ready:
        if source.proc is not None and source.proc.exited and source.proc.holds_slave:
            # No more data will come to make it readable, so read again until a read finds
            # nothing, which releases the slave.
            source.ready = True
            _schedule_pump()
        else:
            _watch(source)
    if asyncio.iscoroutine(result):
        task = asyncio.ensure_future(result)
        PUMP_TASKS.add(task)
        task.add_done_callback(PUMP_TASKS.discard)

def _wait_for_more(source):
    """Nothing to read now. If the program has exited, its output is all read, so the framer
    lets go of the slave and end of output follows once no other process holds it."""
    source.ready = False
    if source.proc is not None and source.proc.exited:
        source.proc.release_slave()
    _watch(source)

def _retry_echo_after(delay):
    global ECHO_TIMER
    if ECHO_TIMER is not None:
        return
    def fire():
        global ECHO_TIMER
        ECHO_TIMER = None
        _schedule_pump()
    ECHO_TIMER = asyncio.get_event_loop().call_later(delay, fire)

def flow_changed():
    """Call after anything that can add credit or start or end a drain."""
    if IT2_GATE is not None:
        if it2_may_read():
            IT2_GATE.set()
        else:
            IT2_GATE.clear()
    _schedule_flow_tick()
    if FLOW.has_credit():
        _schedule_pump()

def flow_grant(n, flow=FLOW_LEADER):
    if isinstance(flow, int):
        proc = PROCESSES.get(flow)
        if proc is None or not proc.pane:
            # The pane ended, or never was one: nothing may spend this.
            return
    FLOW.grant(n, flow)
    flow_changed()

def _schedule_flow_tick():
    global FLOW_TICK_HANDLE
    if FLOW_TICK_HANDLE is not None or not FLOW.enabled:
        return
    FLOW_TICK_HANDLE = asyncio.get_event_loop().call_later(FLOW_TICK, _flow_tick)

def _flow_tick():
    global FLOW_TICK_HANDLE
    FLOW_TICK_HANDLE = None
    waiting = {s.flow for s in SOURCES if s.ready}
    if FLOW.tick(waiting):
        q = lock()
        send_esc(q, '%notif valve')
        unlock(q)
    flow_changed()

def it2_may_read():
    """In version 1, it2 data is not under credit, but it must not fill the path while a drain
    is measuring it empty. In version 2 it reads only with credit of its own."""
    if FLOW.draining:
        return False
    return FLOW.budget(FLOW_IT2) > 0

async def it2_gate():
    """Waits until it2 data may be read."""
    global IT2_GATE
    if IT2_GATE is None:
        IT2_GATE = asyncio.Event()
        if it2_may_read():
            IT2_GATE.set()
    await IT2_GATE.wait()

def _parse_flow(token):
    if token in (FLOW_LEADER, FLOW_IT2):
        return token
    pid = int(token)
    if pid <= 0:
        raise ValueError(token)
    return pid

def _parse_grant(lines):
    """(flow, byte count) if lines (ending in a blank line) are a grant command, else None.
    `grant <bytes>` is the leader's; `grant <flow> <bytes>` names the flow."""
    args = []
    for line in lines:
        if not line:
            continue
        if args and args[-1].endswith("\\"):
            args[-1] = args[-1][:-1] + line
        else:
            args.append(line)
    try:
        if len(args) not in (2, 3) or base64.b64decode(args[0]) != b'grant':
            return None
        decoded = [base64.b64decode(arg).decode('utf-8') for arg in args[1:]]
        flow = _parse_flow(decoded[0]) if len(decoded) == 2 else FLOW_LEADER
        n = int(decoded[-1])
    except Exception:
        return None
    return (flow, n) if n >= 0 else None

def command_reader(stream, loop, queue):
    """Reads commands on a thread of its own. A grant takes effect as soon as it is read, even
    while a command handler is still running, and gets no reply. Every other line is queued
    for mainloop unchanged. None marks the end of input."""
    pending = []
    while True:
        try:
            raw = stream.readline()
        except Exception:
            raw = ''
        if raw == '':
            loop.call_soon_threadsafe(queue.put_nowait, None)
            return
        line = raw.rstrip('\n')
        pending.append(line)
        if line:
            continue
        grant = _parse_grant(pending)
        if grant is not None:
            flow, n = grant
            loop.call_soon_threadsafe(flow_grant, n, flow)
        else:
            if len(pending) > 1:
                loop.call_soon_threadsafe(FLOW.note_command)
            for pending_line in pending:
                loop.call_soon_threadsafe(queue.put_nowait, pending_line)
        pending = []

class Process:
    @staticmethod
    async def run_tty(executable, args, cwd, env, window_size=None):
        """window_size is a packed struct winsize; None means the framer's own size."""
        master, slave = pty.openpty()
        try:
            def set_ctty(ctty_fd, master_fd):
                os.setsid()
                os.close(master_fd)
                fcntl.ioctl(ctty_fd, termios.TIOCSCTTY, 0)
                size = window_size
                if size is None:
                    size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, '00000000')
                fcntl.ioctl(ctty_fd, termios.TIOCSWINSZ, size)
            log(env)
            log(f'create subprocess args={args} cwd={cwd} executable={executable}')
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                cwd=cwd,
                env=env,
                executable=executable,
                preexec_fn=lambda: set_ctty(slave, master))
        except BaseException:
            os.close(slave)
            raise
        return await Process.run_tty_proc(proc, master, slave, f'run_tty({args})')

    @staticmethod
    async def run_shell_tty(command):
        master, slave = pty.openpty()
        try:
            env = dict(os.environ)
            env["LANG"] = "C"
            # A process group of its own lets a signal reach everything the shell started.
            # /bin/sh does not always exec a lone command (dash forks it), and signaling only
            # the shell would leave the program running. Not a new session: a session leader
            # can take the pty as its controlling terminal, and then its exit waits for
            # output the framer may not have credit to read.
            proc = await asyncio.create_subprocess_shell(
                command,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                env=env,
                preexec_fn=os.setpgrp)
        except BaseException:
            os.close(slave)
            raise
        return await Process.run_tty_proc(proc, master, slave, f'run_shell_tty({command})',
                                          group=True)

    @staticmethod
    async def run_tty_proc(proc, master, slave, descr, group=False):
        pipe = open(master, 'wb', 0)
        writer = await Process._writer(pipe)
        # Output is read straight from master by the pump (see FlowSource), not through a
        # stream reader: asyncio's pipe transport reads up to 256 KB at a time and keeps
        # reading after pause_reading(), which would take more than the credit allows.
        return Process(proc, writer, master=master, slave=slave, descr=descr, group=group)

    @staticmethod
    async def writer(fd):
        pipe = open(fd, 'wb', 0)

        return await Process._writer(pipe)

    @staticmethod
    async def _writer(pipe):
        loop = asyncio.get_event_loop()
        transport, protocol = await loop.connect_write_pipe(asyncio.Protocol, pipe)
        writer = asyncio.StreamWriter(
                transport=transport,
                protocol=protocol,
                reader=None,
                loop=loop)
        return writer

    def __init__(self, process, writer, master=None, slave=None, descr="", group=False):
        self.__process = process
        # The framer's own copy of the pty's slave end, kept until the program has exited and
        # its output has been read. macOS discards unread output when the last copy of the
        # slave closes, which would lose whatever a program wrote just before it exited, or
        # all it wrote while the framer had no credit to read it.
        self.__slave = slave
        self.__exit_task = None
        # Signals go to the whole process group, which the process leads.
        self.__group = group
        self.__writer = writer
        self.flow_source = None
        self.__cleanup = []
        self.__return_code = None
        self.__master = master
        self.__descr = descr
        self.echo = True
        self.icanon = True
        self.login = False
        # A pane process (see handle_pane) has its own window size and output channel.
        self.pane = False

    @property
    def master(self):
        return self.__master

    async def cleanup(self):
        log(f'cleanup {self.__descr}: cleanup process {self.pid}')
        if self.__return_code is None:
            self.__return_code = self.__process.returncode
            log(f'nonblocking return code is {self.__return_code}')
        if self.__return_code is None:
            log(f'kill {self.__descr}')
            try:
                # Use os.kill directly to avoid asyncio bug with send_signal on dead processes
                # https://github.com/python/cpython/issues/87744
                # https://bugs.python.org/issue38630
                if not self.__group or not self._signal_group(signal.SIGKILL):
                    os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                log(f'cleanup {self.__descr}: process already dead')
            except Exception as e:
                log(f'cleanup {self.__descr}: exception {e} during kill')
            log(f'cleanup {self.__descr}: wait')
            await self.wait()
        # Stop reading before the writer closes master, which the source reads from.
        if self.flow_source is not None:
            remove_source(self.flow_source)
        if self.__exit_task is not None:
            self.__exit_task.cancel()
        self.release_slave()
        log(f'cleanup {self.__descr}: close writer tx')
        self.__writer.transport.close()
        log(f'cleanup {self.__descr}: running cleanup callbacks')

        # StreamReader doesn't have a transport so it must be closed by a __cleanup function.
        for f in self.__cleanup:
            f()
        log(f'cleanup {self.__descr}: done')

    def add_cleanup(self, coro):
        self.__cleanup.append(coro)

    async def kill(self, signal):
        self.send_signal(signal)

    async def wait(self):
        rc = await self.__process.wait()
        self.__return_code = rc
        return rc

    @property
    def return_code(self):
        return self.__return_code

    @property
    def pid(self):
        return self.__process.pid

    async def handle_read(self, callback):
        """callback(channel, data, exempt) gets each read; empty data means end of output."""
        self.flow_source = FlowSource(self.__master, callback, 1, self)
        add_source(self.flow_source)
        if self.__slave is not None:
            self.__exit_task = asyncio.ensure_future(self._await_exit())

    async def _await_exit(self):
        await self.wait()
        log(f'{self.__descr} exited; release the slave once its output is read')
        # The pump releases the slave when a read finds nothing left.
        source = self.flow_source
        if source is not None and not source.closed:
            _unwatch(source)
            source.ready = True
            _schedule_pump()

    @property
    def exited(self):
        return self.__process.returncode is not None

    @property
    def holds_slave(self):
        return self.__slave is not None

    def release_slave(self):
        if self.__slave is not None:
            os.close(self.__slave)
            self.__slave = None

    async def write(self, data):
        self.__writer.write(data)

    def send_signal(self, signal):
        if self.__group and self._signal_group(signal):
            return
        try:
            self.__process.send_signal(signal)
        except ProcessLookupError:
            # It has exited and been reaped, which now happens before its output ends.
            log(f'send_signal {self.__descr}: already exited')

    def hang_up(self):
        """What closing a terminal does to the session on it: SIGHUP, then SIGCONT so a stopped
        job sees it, to the process group the program leads. An interactive shell ignores
        SIGTERM but not SIGHUP, and passes the hangup on to its jobs."""
        for sig in (signal.SIGHUP, signal.SIGCONT):
            if not self._signal_group(sig):
                self.send_signal(sig)

    def _signal_group(self, sig):
        """Returns whether the group got the signal. macOS fails with EPERM when only an
        unreaped zombie is left, as does any system when no member may be signaled (a lone
        sudo); the caller then signals the process alone, as it would without a group."""
        try:
            os.killpg(self.pid, sig)
            return True
        except (ProcessLookupError, PermissionError) as e:
            log(f'signal group of {self.__descr}: {e}')
            return False

## Login Shell

def guess_login_shell():
    path = pwd.getpwuid(os.geteuid()).pw_shell
    if os.access(path, os.X_OK):
        return path
    return "/bin/sh"

# Set from IT2_PUT_BIN_ON_PATH by claim_put_bin_flag; see login_shell_environment.
PUT_IT2_BIN_ON_PATH = False

def claim_put_bin_flag():
    """Take IT2_PUT_BIN_ON_PATH out of the framer's own environment, remembering it. The flag is
    the framer's: left in os.environ, every process the framer starts would inherit it."""
    global PUT_IT2_BIN_ON_PATH
    PUT_IT2_BIN_ON_PATH = os.environ.pop("IT2_PUT_BIN_ON_PATH", None) == "1"

def login_shell_environment():
    """The framer's environment for a login shell it starts.

    iTerm2 sets IT2_PUT_BIN_ON_PATH when the shell gets it2 uploaded to ~/.iterm2/bin but no
    shell-integration script to put that directory on PATH (tcsh, which can't be injected).
    PATH itself can't come from iTerm2: it arrives by setenv in conductor.sh, which needs its
    own PATH, and the value is never re-expanded. So the prepend happens here, where the real
    PATH is known, before the shell's own login files run (which may reorder it: macOS's
    path_helper in /etc/csh.login does)."""
    env = dict(os.environ)
    if not PUT_IT2_BIN_ON_PATH:
        return env
    bin_dir = os.path.join(os.path.expanduser("~"), ".iterm2", "bin")
    if not os.path.isdir(bin_dir):
        return env
    path = env.get("PATH")
    rest = [] if not path else [d for d in path.split(":") if d != bin_dir]
    env["PATH"] = ":".join([bin_dir] + rest)
    return env

## Process monitoring

async def autopoll(delay):
    try:
        global AUTOPOLL
        while True:
            log('autopoll: call poll()')
            cats = await poll()
            if not cats:
                log(f'autopoll: sleep for {delay}')
                await asyncio.sleep(delay)
                log(f'autopoll: awoke')
                continue
            # Send poll output and sleep until client requests autopolling again.
            identifier = makeid()
            q = lock()
            send_esc(q, f'%autopoll {identifier}')
            send_poll_output(q, cats)
            send_esc(q, f'%end {identifier}')
            unlock(q)
            AUTOPOLL = 0
            while not AUTOPOLL:
                log(f'autopoll: sleep for {delay}')
                await asyncio.sleep(delay)
                log(f'autopoll: awoke')
    except asyncio.CancelledError:
        log('autopoll canceled')
        raise
    except Exception as e:
        log(f'autopoll threw {e}: {traceback.format_exc()}')

def poll_output_lines(cats):
    for catname in cats:
        yield f'$begin {catname}'
        for line in cats[catname]:
            # Process names come from anyone on the host. Without control characters, one
            # cannot end a frame early or smuggle in a frame of its own.
            yield ''.join('?' if ord(c) < 0x20 or 0x7f <= ord(c) < 0xa0 else c for c in line)

def send_poll_output(q, cats):
    for line in poll_output_lines(cats):
        send(q, line.encode("utf-8") + b'\n')

def get_echo_icanon(tty):
    try:
        attrs = termios.tcgetattr(tty)
        return (bool(attrs[3] & termios.ECHO), bool(attrs[3] & termios.ICANON))
    except Exception as e:
        log(f'get_echo_icanon threw {e}: {traceback.format_exc()}')
        raise

async def watch_tty(proc, delay):
    try:
        while True:
            log("watch_tty: poll")
            poll_tty(proc)
            await asyncio.sleep(delay)
    except asyncio.CancelledError:
        log('watch_tty canceled')
        raise
    except Exception as e:
        log(f'watch_tty threw {e}: {traceback.format_exc()}')

def poll_tty(proc):
    log(f"Check TTY with fd {proc.master}")
    new_echo, new_icanon = get_echo_icanon(proc.master)
    if new_echo != proc.echo or new_icanon != proc.icanon:
        log(f'echo: {proc.echo}->{new_echo}, icanon: {proc.icanon}->{new_icanon}')
        parts = [
            ('+' if new_echo else '-') + 'echo',
            ('+' if new_icanon else '-') + 'icanon']
        print_tty(" ".join(parts))
    proc.echo = new_echo
    proc.icanon = new_icanon

async def poll():
    result = {}
    ps_out = await poll_ps()
    if ps_out is not None:
        result["ps"] = ps_out
    cpu_time_diff = await poll_cpu()
    if cpu_time_diff is not None:
        result["cpu"] = cpu_time_diff
    return result

mpstat_exists = None  # Global variable to cache the mpstat existence check

async def check_mpstat_exists():
    global mpstat_exists
    if mpstat_exists is None:
        try:
            log("Checking if mpstat exists")
            proc = await asyncio.create_subprocess_shell(
                "mpstat -V",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            output, _ = await proc.communicate()
            log(f'return code is {proc.returncode}')
            mpstat_exists = proc.returncode == 0
        except FileNotFoundError:
            log("mpstat: file not found")
            mpstat_exists = False


async def poll_cpu():
    operating_system = platform.system()
    if operating_system == 'Darwin':  # macOS
        command = "top -l 1 -n 0 | awk '/CPU usage/ {print $3}'"
    elif operating_system == 'Linux':  # Linux
        await check_mpstat_exists()
        if not mpstat_exists:
            return None
        command = "mpstat -P ALL 1 1 | awk '/Average:/ && $2 == \"all\" {print 100 - $NF}'"
    else:
        return None
    env = dict(os.environ)
    env["LANG"] = "C"
    proc = await asyncio.create_subprocess_shell(
        command,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env)
    log(f'poll_cpu: run {command} {proc}')
    output, erroutput = await proc.communicate()
    if proc.returncode == 0:
        log(f'poll_cpu: successful return')
        # Parse the output here
        final = "=" + output.decode("utf-8").strip()
        log(f'poll_cpu: return parsed output')
        return [final]
    log(f'poll_cpu: {command} failed with {proc.returncode}')
    return None

async def poll_ps():
    env = dict(os.environ)
    env["LANG"] = "C"
    # -A, POSIX for "every process". Not -e: Linux and macOS read it the same way, but FreeBSD
    # and OpenBSD read it as "also print each process's environment", which put every variable
    # (IT2_NONCE among them) in front of each command and made the first one its name.
    proc = await asyncio.create_subprocess_shell(
        "ps -Ao pid,ppid,stat,lstart,command",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env)
    log(f'poll_ps: run ps {proc}')
    output, erroutput = await proc.communicate()
    if proc.returncode == 0:
        log(f'poll_ps: successful return')
        rows = procmon_rows(output)
        await mark_foreground_jobs_off_the_terminal(rows)
        final = procmon_diff(rows)
        log(f'poll_ps: return parsed output')
        return final
    log(f'poll_ps: ps failed with {proc.returncode}')
    return None

# Appended to a process's stat when it is in the terminal's foreground process group but neither
# its stdin nor its stdout is a terminal, like the caffeinate claude starts with its stdio sent to
# /dev/null, or an MCP server piped to its parent. iTerm2 names a session's job after the deepest
# foreground job that IS on the terminal, as it does for local sessions by looking at the fds.
# Not a character ps uses in stat.
OFF_TERMINAL_MARKER = "!"

# (pid, start time, command) -> whether its stdin or stdout is a terminal, or None when unknown.
# A process keeps its stdio, so each is looked up once; the command is in the key so one that
# execs something else (a child that moved its stdio to /dev/null and became caffeinate) is
# looked up again.
STDIO_ON_TERMINAL = {}

def has_proc_fds():
    """Whether this host has /proc/<pid>/fd (Linux). Otherwise lsof is asked."""
    return os.path.isdir("/proc/self/fd")

def stdio_is_terminal(path):
    return path.startswith("/dev/pts/") or path.startswith("/dev/tty")

def proc_stdio_on_terminal(pid):
    """From /proc (Linux): True or False, or None when /proc can't say."""
    paths = []
    for fd in (0, 1):
        try:
            paths.append(os.readlink("/proc/%s/fd/%d" % (pid, fd)))
        except OSError:
            pass
    if not paths:
        return None
    return any(stdio_is_terminal(p) for p in paths)

def parse_lsof_stdio(output):
    """pid -> whether fd 0 or 1 is a terminal, from `lsof -F fn` output for fds 0 and 1."""
    result = {}
    pid = None
    for line in output.splitlines():
        if line.startswith("p"):
            pid = line[1:]
            result.setdefault(pid, False)
        elif line.startswith("n") and pid is not None:
            if stdio_is_terminal(line[1:]):
                result[pid] = True
    return result

async def lsof_stdio_on_terminal(pids):
    """For hosts without /proc (macOS, BSD): pid -> True or False, for the pids lsof could see."""
    proc = None

    async def stop():
        # A lsof that hangs (a stale network mount, say) must not outlive the question.
        if proc is not None and proc.returncode is None:
            with contextlib.suppress(Exception):
                proc.kill()
            # Bounded: SIGKILL waits for a process stuck in the kernel to come back out.
            with contextlib.suppress(Exception):
                await asyncio.wait_for(proc.wait(), 1)

    try:
        proc = await asyncio.create_subprocess_exec(
            "lsof", "-w", "-b", "-n", "-P", "-a", "-d", "0,1", "-p", ",".join(pids), "-F", "fn",
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL)
        output, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
    except asyncio.CancelledError:
        # Before Python 3.8 this is an Exception, and swallowing it below would keep autopoll
        # running after quit cancelled it.
        await stop()
        raise
    except Exception as e:
        log(f'lsof_stdio_on_terminal: {e}')
        await stop()
        return {}
    return parse_lsof_stdio(output.decode("utf-8", "replace"))

async def mark_foreground_jobs_off_the_terminal(rows):
    """Append OFF_TERMINAL_MARKER to the stat of each foreground process (+ in stat) whose stdio
    is not a terminal. One that can't be checked is left unmarked, which is how it was before."""
    global STDIO_ON_TERMINAL
    live = {}
    unknown = []
    for pid, row in rows.items():
        if "+" not in row[2]:
            continue
        key = (pid, row[3], row[4])
        if key in STDIO_ON_TERMINAL:
            live[key] = STDIO_ON_TERMINAL[key]
            continue
        if has_proc_fds():
            live[key] = proc_stdio_on_terminal(pid)
        else:
            unknown.append(pid)
            live[key] = None
    if unknown:
        found = await lsof_stdio_on_terminal(unknown)
        for pid in unknown:
            live[(pid, rows[pid][3], rows[pid][4])] = found.get(pid)
    STDIO_ON_TERMINAL = live
    for (pid, _, _), on_terminal in live.items():
        if on_terminal is False:
            row = rows[pid]
            rows[pid] = (row[0], row[1], row[2] + OFF_TERMINAL_MARKER, row[3], row[4])

async def register(pid):
    global REGISTERED
    if pid in REGISTERED:
        return
    REGISTERED.append(pid)
    log(f'After registering {pid} REGISTERED={REGISTERED}')

async def deregister(pid):
    global REGISTERED
    if pid in REGISTERED:
        REGISTERED.remove(pid)

def procmon_parse(output):
    return procmon_diff(procmon_rows(output))

def procmon_rows(output):
    """pid -> (pid, ppid, stat, start time, command) for the registered pids' subtrees."""
    output = output.decode("utf-8")
    lines = output.split("\n")
    whitespace = r'\s+'
    number = r'\d+'
    nonspace = r'\S+'
    letters = r'[A-Za-z]+'
    pattern = "".join(
        [r'^',
         r'\s*',
         r'(',
         number,  # pid [capture 1]
         r')',
         whitespace,
         r'(',
         number,  # ppid [capture 2]
         r')',
         whitespace,
         r'(',
         nonspace,  # stat [capture 3]
         r')',
         whitespace,
         r'(',
         letters,  # day of week  [capture 4]
         whitespace,
         letters,  # name of month
         whitespace,
         number,  # day of month
         whitespace,
         number,  # hh
         r':',
         number,  # mm
         r':',
         number,  # ss
         whitespace,
         number,  # yyyy
         r')',
         whitespace,
         r'(.*)'  # command  [capture 5]
    ])
    def parse(line):
        match = re.search(pattern, line)
        if not match:
            return None
        return (match.group(1), match.group(2), match.group(3), match.group(4), match.group(5))
    rows = map(parse, lines)
    # pid->ppid
    parent={}
    # ppid->[pid]
    children={}
    # pid->row
    index={}
    for row in rows:
        if row is None:
            continue
        if row[4].startswith("(") and row[4].endswith(")"):
            log(f'procmon_parse: ignore defunct {row}')
            continue
        pid = row[0]
        ppid = row[1]
        parent[pid] = ppid
        children[ppid] = children.get(ppid, []) + [pid]
        index[pid] = row
    log(f'procmon_parse: {len(index)} valid rows')
    # pid -> row
    results = {}
    def add(pid):
        results[pid] = index[pid]
        for child in children.get(pid, []):
            add(child)
    for pid in REGISTERED:
        log(f'procmon_parse: Add hierarchy starting at {pid}')
        if str(pid) in index:
            add(str(pid))
    log(f'procmon_parse: {len(results)} processes in output')
    return results

def procmon_diff(results):
    """The edits since the last poll: +row for a new process, -pid for a gone one, ~row for a
    changed one."""
    global LASTPS
    last = dict(LASTPS)
    LASTPS = dict(results)

    def diff():
        currentkeys = set(results.keys())
        lastkeys = set(last.keys())
        log(f'procmon_parse: diff current={currentkeys} last={lastkeys}')
        for addition in currentkeys - lastkeys:
            log(f'procmon_parse: add {addition}')
            yield "+" + " ".join(map(str, results[addition]))
        for removal in lastkeys - currentkeys:
            log(f'procmon_parse: remove {removal}')
            yield "-" + str(removal)
        for pid in results:
            if pid in last and results[pid] != last[pid]:
                log(f'procmon_parse: edit {pid}')
                yield "~" + " ".join(map(str, results[pid]))
    return list(diff())


async def get_env_var(var_name):
    """The variable as the user's shell sets it, or None when that cannot be learned."""
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', var_name):
        log(f'Not a variable name: {var_name!r}')
        return None
    # Get the user's shell
    user_shell = os.environ.get('SHELL', '/bin/bash')

    # Non-POSIX shells may leave POSIX shell path in the $SHELL; perform an additional check.
    # Keep a full path to the shell, which may not be on the framer's PATH.
    if os.environ.get('XONSHRC', ''):
        if os.path.basename(user_shell) != 'xonsh':
            user_shell = 'xonsh'
    elif os.environ.get('NU_VENDOR_AUTOLOAD_DIR', ''):
        if os.path.basename(user_shell) != 'nu':
            user_shell = 'nu'

    known_shells = ['bash', 'csh', 'dash', 'fish', 'ksh', 'nu', 'sh', 'tcsh', 'xonsh', 'zsh']

    # Extract the last path component of the user's shell
    shell_name = os.path.basename(user_shell)
    log(f'Shell is {user_shell}')

    if shell_name not in known_shells:
        log(f'Unknown shell {shell_name}')
        return None

    if shell_name == 'nu':
        # nushell keeps the environment under $env and has no $VAR syntax. It also converts
        # PATH-like variables to lists, which print renders as a table, so join them back.
        command = (f'print ($env.{var_name}? | default "" | '
                   'if ($in | describe | str starts-with "list") { str join (char esep) } else { into string })')
    elif shell_name == 'xonsh':
        # xonsh does not expand variables inside quotes.
        command = f'echo ${var_name}'
    else:
        # Quoted so the value is not split or globbed, and printf rather than echo, which
        # may take a value such as -n as an option or interpret backslashes.
        command = f'printf "%s\\n" "${var_name}"'

    try:
        process = await asyncio.create_subprocess_exec(
            user_shell, '-c', command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )

        stdout, stderr = await process.communicate()
        if process.returncode != 0:
            log(f'get_env_var({var_name}): {user_shell} exited {process.returncode}: {stderr!r}')
            return None
        value = stdout.decode()
        return value[:-1] if value.endswith('\n') else value
    except Exception as e:
        log(f'get_env_var({var_name}) threw: {traceback.format_exc()}')
        return None

def write_exec_file(code):
    """Writes `code` to a new hidden file in ~/.iterm2, executable and private to the user, and
    returns its path. Not /tmp: on a shared host that may be full or unwritable, and everything
    else iTerm2 writes on a host lives in ~/.iterm2. The code (a jump script, say) removes the
    file itself once it is running; see Conductor.jumpScript."""
    directory = os.path.expanduser("~/.iterm2")
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, path = tempfile.mkstemp(dir=directory, prefix=".eval-")
    try:
        os.write(fd, code.encode("utf-8", "surrogateescape"))
        os.fchmod(fd, 0o700)
    finally:
        os.close(fd)
    return path

# Run the async function
async def save_and_exec(identifier, code):
    log("begin save_and_exec")
    try:
        tmpname = write_exec_file(code)
        log(f'save_and_exec: tmp={tmpname}')

        e = dict(os.environ)
        e["SELF"] = tmpname
        await run_login_shell(identifier, "/bin/sh", ["sh", tmpname], os.getcwd(), e)
    except Exception as e:
        log(f'save_and_exec: {traceback.format_exc()}')
        q = begin(identifier)
        send_esc(q, f'Command failed: {e}')
        end(q, identifier, 1)

## Commands

EXEC_LOGIN_MARKER = "--iterm2-exec-login"

async def handle_login(identifier, args):
    log("begin handle_login")
    cwd = args[0]
    args = args[1:]
    log(f'cwd={cwd} args={args}')
    cwd = os.path.expandvars(os.path.expanduser(cwd))
    if args and args[0] == EXEC_LOGIN_MARKER:
        # iTerm2 named the shell and the arguments shell integration gave it (bash's --posix).
        # Start that shell as the login shell itself, so its profile runs in the interactive
        # shell. Through the login shell's -c, the outer shell would source it and exec the
        # interactive one, which would lose what it defines.
        if len(args) < 2:
            q = begin(identifier)
            send_esc(q, f'Command failed: {EXEC_LOGIN_MARKER} without a shell')
            end(q, identifier, 1)
            return False
        shell = args[1]
        argv = ["-" + os.path.basename(shell)] + args[2:]
        return await run_login_shell(identifier, shell, argv, cwd, login_shell_environment())
    had_args = len(args) > 0
    if args:
        args = ["-c", " ".join(args)]
        log(f'Update args to {args}')
    login_shell = guess_login_shell()
    _, shell_name = os.path.split(login_shell)
    argv0 = "-" + shell_name

    return await run_login_shell(identifier, login_shell, [argv0] + args, cwd,
                                 login_shell_environment())

async def run_login_shell(identifier, login_shell, argv, directory, environment):
    log(f'run_login_shell: dir={directory} command={login_shell} argv={argv}')
    try:
        proc = await Process.run_tty(
            login_shell,
            argv,
            directory,
            environment)
        log("login shell started")
        global PROCESSES
        proc.login = True
        PROCESSES[proc.pid] = proc
        q = begin(identifier)
        send_esc(q, proc.pid)
        end(q, identifier, 0)
        await proc.handle_read(make_monitor_process(proc, True))
    except Exception as e:
        log(f'run_login_shell: {e}')
        q = begin(identifier)
        send_esc(q, f'Command failed: {e}')
        end(q, identifier, 1)
    return False

async def handle_run(identifier, args):
    """Run a command inside the user's shell"""
    try:
        proc = await Process.run_shell_tty(args[0])
        global PROCESSES
        PROCESSES[proc.pid] = proc
        q = begin(identifier)
        send_esc(q, proc.pid)
        end(q, identifier, 0)
        await proc.handle_read(make_monitor_process(proc, False))

        start_tty_task(identifier, proc)
    except Exception as e:
        log(f'handle_run: {e}')
        q = begin(identifier)
        end(q, identifier, 1)
    return False

def pack_window_size(rows, cols):
    """A struct winsize for rows x cols, or None unless both are sane."""
    if not (0 < rows <= 10000 and 0 < cols <= 10000):
        return None
    return struct.pack('HHHH', rows, cols, 0, 0)

async def handle_pane(identifier, args):
    """pane <rows> <cols> <cwd> <command> [NAME=value ...]
    Runs command with the login shell on a new pty of its own, as a workgroup peer's program;
    an empty command runs an interactive login shell. Unlike `run` it gets a controlling
    terminal and the framer's environment, plus the variables given (the peer's own
    TERM_SESSION_ID and terminal identity); unlike `login` its output goes out on PANE_CHANNEL,
    it keeps its own window size, and it is never treated as the login shell. Answers with
    the pid."""
    log(f'handle_pane {args}')
    try:
        rows = int(args[0])
        cols = int(args[1])
        cwd = os.path.expandvars(os.path.expanduser(args[2]))
        command = args[3]
        variables = dict(arg.split("=", 1) for arg in args[4:])
    except Exception as e:
        log(f'handle_pane: {e}')
        fail(identifier, "bad arguments")
        return False
    window_size = pack_window_size(rows, cols)
    if window_size is None:
        fail(identifier, "bad arguments")
        return False
    login_shell = guess_login_shell()
    _, shell_name = os.path.split(login_shell)
    argv = ["-" + shell_name] + (["-c", command] if command else [])
    environment = login_shell_environment()
    environment.update(variables)
    try:
        proc = await Process.run_tty(
            login_shell,
            argv,
            cwd,
            environment,
            window_size)
    except Exception as e:
        log(f'handle_pane: {e}')
        q = begin(identifier)
        send_esc(q, f'Command failed: {e}')
        end(q, identifier, 1)
        return False
    proc.pane = True
    PROCESSES[proc.pid] = proc
    q = begin(identifier)
    send_esc(q, proc.pid)
    end(q, identifier, 0)
    await proc.handle_read(make_monitor_process(proc, False))
    return False

async def handle_panes(identifier, args):
    """panes: the pids of the running panes, on one line separated by spaces. A restarted or
    recovered iTerm2 reattaches their sessions with this, and finds any no session claims."""
    q = begin(identifier)
    send_esc(q, " ".join(str(pid) for pid, proc in PROCESSES.items() if proc.pane))
    end(q, identifier, 0)
    return False

async def handle_panesize(identifier, args):
    """panesize <pid> <rows> <cols>: resize a pane process's pty."""
    log(f'handle_panesize {args}')
    try:
        pid = int(args[0])
        window_size = pack_window_size(int(args[1]), int(args[2]))
    except Exception as e:
        log(f'handle_panesize: {e}')
        fail(identifier, "bad arguments")
        return False
    proc = PROCESSES.get(pid)
    if window_size is None or proc is None or not proc.pane or proc.master is None:
        fail(identifier, "no such pane")
        return False
    try:
        fcntl.ioctl(proc.master, termios.TIOCSWINSZ, window_size)
    except OSError as e:
        log(f'handle_panesize: {e}')
        fail(identifier, "resize failed")
        return False
    # The kernel signals only a change of size. A session that reattached sends its size
    # whether or not it changed, so its program redraws what that session missed.
    try:
        os.killpg(os.tcgetpgrp(proc.master), signal.SIGWINCH)
    except OSError as e:
        log(f'handle_panesize: {e}')
    q = begin(identifier)
    end(q, identifier, 0)
    return False

def start_tty_task(identifier, proc):
    proc.tty_task = asyncio.create_task(watch_tty(proc, 1))

def reset():
    global REGISTERED
    global LASTPS
    global AUTOPOLL
    REGISTERED = []
    LASTPS = {}
    AUTOPOLL = 0

async def handle_reset1(identifier, args):
    reset()
    q = begin(identifier)
    end(q, identifier, 0)

async def handle_reset2(identifier, args):
    reset()
    q = begin(identifier)
    send_esc(q, args[0])
    end(q, identifier, 0)

async def handle_save(identifier, args):
    log(f'handle_save {identifier} {args}')
    global RECOVERY_STATE
    try:
        RECOVERY_STATE = dict(s.split('=', 1) for s in args)
        code = 0
    except Exception as e:
        log(f'handle_save: {e}')
        code = 1
    q = begin(identifier)
    end(q, identifier, code)

async def handle_getenv(identifier, args):
    log(f'handle_getenv {identifier} {args}')
    q = begin(identifier)
    value = await get_env_var(args[0])
    if value is None:
        # The framer's own environment came from the login shell, so it is the next best.
        value = os.environ.get(args[0])
    if value is None:
        # iTerm2 records the first line as the value; with none it records nothing.
        end(q, identifier, 1)
        return
    send_esc(q, value)
    end(q, identifier, 0)

async def handle_runpy(identifier, args):
    "args[0] should be a sequence of Python statements returning a string"
    log(f'handle_runpy {identifier} {args}')
    q = begin(identifier)
    try:
        encoded = args[0]
        script = base64.b64decode(encoded).decode('utf-8')
        indented = textwrap.indent(script, '    ')
        wrapper = f"def __f__():\n{indented}"
        env = {}
        exec(wrapper, env)
        output = env['__f__']()
        send_esc(q, str(output) if output is not None else "")
        end(q, identifier, 0)
    except:
        send_esc(q, traceback.format_exc())
        end(q, identifier, 1)

async def handle_eval(identifier, args):
    log(f'handle_eval {identifier} [{len(args[0])} bytes]')
    # surrogateescape here and in write_exec_file writes the script's bytes unchanged.
    await save_and_exec(identifier, base64.b64decode(args[0]).decode('utf-8', 'surrogateescape'))

def make_path(b64path):
    # iTerm2 sends the path's bytes, UTF-8 for a name it typed. fsdecode is the inverse of the
    # fsencode that os functions apply to a str path, so any bytes, UTF-8 or not, reach the
    # filesystem unchanged.
    return os.fsdecode(os.path.expanduser(base64.b64decode(b64path)))

async def handle_file(identifier, args):
    log(f'handle_file {identifier} {args}')
    if len(args) < 2:
        log(f'Not enough args {args}')
        q = begin(identifier)
        end(q, identifier, 1)
        return
    q = begin(identifier)
    sub = args[0]
    log(f'sub is {sub}')
    if sub == "ls":
        await handle_file_ls(q, identifier, make_path(args[1]), args[2])
        return
    if sub == "fetch":
        if len(args) >= 4:
            await handle_file_fetch(q, identifier, make_path(args[1]), int(args[2]), int(args[3]))
        else:
            await handle_file_fetch(q, identifier, make_path(args[1]), 0, float('inf'))
        return
    if sub == "stat":
        await handle_file_stat(q, identifier, make_path(args[1]))
        return
    if sub == "suggest":
        await handle_file_suggest(q,
                                  identifier,
                                  make_path(args[1]),
                                  args[2],
                                  make_path(args[3]),
                                  args[4],
                                  int(args[5]))
        return
    if sub == "rm":
        i = 1
        recursive = False
        while i < len(args) and args[i].startswith("-"):
            if args[i] == "-r":
                recursive = True
            i += 1
        if i == len(args):
            end(q, identifier, 1)
            return
        await handle_file_rm(q, identifier, make_path(args[i]), recursive)
        return
    if sub == "ln":
        await handle_file_ln(
            q,
            identifier,
            make_path(args[1]),
            make_path(args[2]))
        return
    if sub == "mv":
        await handle_file_mv(
            q,
            identifier,
            make_path(args[1]),
            make_path(args[2]))
        return
    if sub == "mkdir":
        await handle_file_mkdir(q, identifier, make_path(args[1]))
        return
    if sub == "create":
        await handle_file_create(q,
                                 identifier,
                                 make_path(args[1]),
                                 base64.b64decode("".join(args[2:])))
        return
    if sub == "append":
        await handle_file_append(q,
                                 identifier,
                                 make_path(args[1]),
                                 base64.b64decode("".join(args[2:])))
        return
    if sub == "utime":
        await handle_file_utime(q,
                                identifier,
                                make_path(args[1]),
                                int(float(args[2])))
        return
    if sub == "chmod-u":
        await handle_file_chmod_u(q,
                                  identifier,
                                  make_path(args[1]),
                                  args[2])
        return
    if sub == "zip":
        await handle_file_zip(q,
                              identifier,
                              make_path(args[1]))
        return
    if sub == "search":
        await handle_file_search(q,
                                 identifier,
                                 args[1:])
        return

    log(f'unrecognized subcommand {sub}')
    end(q, identifier, 1)

def permissions(path):
    return {
        "r": os.access(path, os.R_OK, effective_ids=True),
        "w": os.access(path, os.W_OK, effective_ids=True),
        "x": os.access(path, os.X_OK, effective_ids=True) }

def remotefile(pp, abspath, s):
    if stat.S_ISLNK(s.st_mode):
        k = {"symlink": {"_0": os.readlink(abspath) }}
    elif stat.S_ISDIR(s.st_mode):
        k = {"folder": {}}
    elif stat.S_ISREG(s.st_mode):
        k = {"file": {"_0": {"size": s[stat.ST_SIZE]}}}
    else:
        return None
    to = 978307200
    ctime = s[stat.ST_CTIME] - to
    mtime = s[stat.ST_MTIME] - to
    return {"absolutePath": abspath,
            "kind": k,
            "permissions": permissions(abspath),
            "parentPermissions": pp,
            "ctime": ctime,
            "mtime": mtime}

def file_error(q, identifier, e, path):
    if e is None:
        log(f'file_error {path}')
        end(q, identifier, 1)
        return
    try:
        raise e
    except OSError as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        errors = {errno.EPERM: 1, errno.EACCES: 1, errno.ENOENT: 2, errno.ENOTDIR: 3,
                  errno.ELOOP: 4}
        end(q, identifier, errors.get(e.errno, 100))
    except Exception as e:
        log(f'file_error {path}: {traceback.format_exc()}')
        end(q, identifier, 255)

async def handle_file_ls(q, identifier, path, sorting):
    log(f'handle_file_ls {identifier} {path}')
    try:
        pp = permissions(path)
        files = [(os.path.join(path, f),
                  os.stat(os.path.join(path, f), follow_symlinks=False))
                  for f in os.listdir(path)]
        def fmt(t):
            return remotefile(pp, t[0], t[1])

        obj = list(filter(lambda x: x is not None, map(fmt, files)))
        def sort_ls(d):
            if sorting == 'n':
                return d['absolutePath']
            return d['mtime']
        obj = sorted(obj, key=sort_ls)
        log(f'After sorting contents of {path} are {obj}')
        send_esc(q, "[")
        first = True
        for entry in obj:
            if first:
                first = False
            else:
                send_esc(q, ",")
            j = json.dumps(entry)
            send_esc(q, j)
        send_esc(q, "]")
        end(q, identifier, 0)
        log("handle_file_ls completed normally")
    except Exception as e:
        file_error(q, identifier, e, path)

def remote_file_json(path):
    pp = permissions(os.path.abspath(os.path.join(path, os.pardir)))
    s = os.stat(path, follow_symlinks=False)
    obj = remotefile(pp, path, s)
    return json.dumps(obj)

def send_remote_file(q, path):
    send_esc(q, remote_file_json(path))

async def handle_file_stat(q, identifier, path):
    log(f'handle_file_stat {identifier} {path}')
    try:
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_suggest(q, identifier, prefix, directories, pwd, permissions, max_count):
    log(f'handle_file_suggest({identifier}, {prefix}, {directories}, {pwd}, {permissions})')
    combined = []
    for relative_directory in decode_base64_directories(directories):
        if relative_directory.startswith('/'):
            log(f'relative directory is absolute {relative_directory}')
            directory = relative_directory
        else:
            log(f'relative directory is relative {relative_directory}')
            if not pwd:
                log(f'no pwd {pwd}')
                continue
            directory = os.path.join(pwd, relative_directory)
            log(f'joined directory is {directory}')
        temp = await really_find_completions_with_prefix(prefix, directory, max_count, 'x' in permissions)
        temp.sort()
        combined.extend([remove_prefix(entry, prefix) for entry in temp])
        if len(combined) >= max_count:
            break
    combined = combined[:max_count]
    log(f'Return suggestions: {combined}')
    send_esc(q, json.dumps(combined))
    end(q, identifier, 0)

def remove_prefix(s, prefix):
    # str.removeprefix is new in Python 3.9 and the framer must run on 3.7.
    return s[len(prefix):] if prefix and s.startswith(prefix) else s

def decode_base64_directories(encoded_directories):
    decoded_directories = []
    directories = encoded_directories.split()

    for directory in directories:
        decoded_directory = base64.b64decode(directory).decode('utf-8')
        decoded_directories.append(decoded_directory)

    return decoded_directories

async def really_find_completions_with_prefix(prefix, directory, max_count, executable):
    log(f'really_find_completions_with_prefix({prefix}, {directory}, {max_count}, {executable}')
    if not prefix.startswith('/') and directory.startswith('/'):
        log('Prefix is relative and directory is absolute. Recurse.')
        temp = await really_find_completions_with_prefix(
            os.path.join(directory, prefix), '', max_count, executable)
        prefix_to_remove = directory if directory.endswith('/') else directory + '/'
        return [remove_prefix(entry, prefix_to_remove) for entry in temp]

    if prefix.endswith('/'):
        log('Prefix ends in slash')
        return await contents_of_directory(prefix, '', executable, max_count)

    results = []
    is_directory = False
    exists = os.path.exists(prefix)
    if exists:
        is_directory = os.path.isdir(prefix)
        if is_directory:
            results.append(prefix + '/')

    container = os.path.dirname(prefix)
    if len(container) == 0:
        log(f"No dirname for {prefix}")
        return results

    log("Add contents of directory using prefix basename")
    results.extend(await contents_of_directory(container, os.path.basename(prefix), executable, max_count))
    return results

async def contents_of_directory(directory, prefix, executable, max_count):
    log(f'contents_of_directory({directory}, {prefix}, {executable}, {max_count}')
    try:
        relative = await asyncio.get_event_loop().run_in_executor(None, lambda: os.listdir(directory))
        result = []
        for path in relative:
            if len(result) >= max_count:
                break
            file_name = os.path.basename(path)
            if len(prefix) == 0 or file_name.startswith(prefix):
                full_path = os.path.join(directory, path)
                if not executable or os.access(full_path, os.X_OK):
                    result.append(full_path)
        return result
    except Exception as e:
        log(f'exception while getting contents of {directory}: {traceback.format_exc()}')
        return []

async def handle_file_zip(q, identifier, path):
    log(f'handle_file_zip {identifier} {path}')

    if not os.path.isdir(path):
        log(f'{path} is not a directory')
        file_error(q, identifier, None, f'{path} is not a directory')
        return
    try:
        # Create a temporary file in the user's home directory
        temp_file = tempfile.NamedTemporaryFile(dir=os.path.expanduser("~"), prefix=".", delete=False)
        log(f'zip to {temp_file}')
        ziph = zipfile.ZipFile(temp_file.name, 'w', zipfile.ZIP_DEFLATED)
        log('Opened zip for writing')
    except Exception as e:
        file_error(q, identifier, e, "While creating a temporary file under your home directory")
        return

    try:
        for root, dirs, files in os.walk(path):
            for file in files:
                try:
                    full_path = os.path.join(root, file)
                    log('add {full_path}')
                    ziph.write(full_path,
                               os.path.relpath(os.path.join(root, file),
                                               os.path.join(path, '..')))
                except Exception as e:
                    log(f'Failed to add {file}: {e}')
                    # zip as much as possible. Errors are just ignored, which isn't great.
                    pass
        log('Done zipping')
    except Exception as e:
        file_error(q, identifier, e, temp_file)
    finally:
        log('close zip')
        ziph.close()
        log('send tempfile name')
        send_esc(q, temp_file.name)
        end(q, identifier, 0)

class Search:
    def __init__(self, query: str, basedir: str):
        self.query = query
        self.basedir = basedir
        self.id = makeid()
        self.canceled = False

        # allow up to `window_size` in-flight notifications
        self.window_size = 16
        self.sema = threading.BoundedSemaphore(self.window_size)

        self.task = asyncio.create_task(self.mainloop())
        self.loop: asyncio.AbstractEventLoop

    def emit(self, json: str) -> None:
        q = lock()
        send_esc(q, f'%notif search {self.id} {json}')
        unlock(q)

    def ack(self, count: int) -> None:
        # release up to `count` permits (never exceed window_size)
        for _ in range(count):
            try:
                self.sema.release()
            except ValueError:
                break

    def cancel(self) -> None:
        self.canceled = True
        # ensure any blocked acquire unblocks
        try:
            self.sema.release()
        except ValueError:
            pass

    async def mainloop(self) -> None:
        self.loop = asyncio.get_running_loop()
        done = self.loop.create_future()

        def scan():
            try:
                self._scan_sync()
            except Exception as e:
                log(f"[Search {self.id}] error: {e!r}")
            finally:
                # Queued after the matches, so they are all written before the task ends.
                with contextlib.suppress(RuntimeError):
                    self.loop.call_soon_threadsafe(
                        lambda: done.done() or done.set_result(None))
        # A daemon thread, unlike an executor's, does not keep the framer from exiting while
        # the scan waits for acks that will never come.
        threading.Thread(target=scan, name=f"Search-{self.id}", daemon=True).start()
        await done

    def _scan_sync(self) -> None:
        stack = [self.basedir]
        while stack and not self.canceled:
            path = stack.pop()
            try:
                log(f"Scan {path} for {self.query}")
                with os.scandir(path) as it:
                    for entry in it:
                        if self.canceled:
                            return
                        try:
                            if entry.is_dir(follow_symlinks=False):
                                stack.append(entry.path)
                            elif entry.is_file(follow_symlinks=False) and self.query in entry.name:
                                # block here if we've hit window_size
                                self.sema.acquire()
                                if self.canceled:
                                    return
                                log(f"Found match: {entry.name} for {self.query}")
                                json = remote_file_json(entry.path)
                                try:
                                    self.loop.call_soon_threadsafe(self.emit, json)
                                except RuntimeError:
                                    # The event loop is gone: the framer is exiting.
                                    return
                        except OSError:
                            continue
            except OSError:
                continue

async def handle_file_search(q, identifier, args):
    """Operate on searches, which run in the background.

    search start <query> <base dir>
    search ack <id> <count>
    search stop <id>
    """
    log(f'handle_file_search {identifier} {args}')
    operation = args[0]
    global SEARCH_TASK
    if operation == "start":
        query = args[1]
        basedir = make_path(args[2])
        if SEARCH_TASK:
            SEARCH_TASK.cancel()
            SEARCH_TASK = None
        SEARCH_TASK = Search(base64.b64decode(query).decode('utf-8'), basedir)
        send_esc(q, SEARCH_TASK.id)
    elif operation == "ack":
        id = args[1]
        count = int(args[2])
        if SEARCH_TASK and SEARCH_TASK.id == id:
            SEARCH_TASK.ack(count)
    elif operation == "stop":
        id = args[1]
        if SEARCH_TASK and SEARCH_TASK.id == id:
            if SEARCH_TASK:
                SEARCH_TASK.cancel()
                SEARCH_TASK = None
    end(q, identifier, 0)

async def handle_file_fetch(q, identifier, path, offset, size):
    log(f'handle_file_fetch {identifier} {path}')
    try:
        with open(path, "rb") as f:
            if offset > 0:
                f.seek(offset)
            if size == float('inf'):
                content = f.read()
            else:
                content = f.read(size)
            log(type(content))
            encoded = base64.encodebytes(content).decode('utf8')
            for line in encoded.split("\n"):
                log(f'will send f{type(line)}')
                send_esc(q, line)
        log("ending")
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_rm(q, identifier, path, recursive):
    log(f'handle_file_rm {identifier} {path} {recursive}')
    try:
        # A symlink is removed itself, never what it points to, even when that is a directory.
        if os.path.isdir(path) and not os.path.islink(path):
            if recursive:
                shutil.rmtree(path)
            else:
                os.rmdir(path)
        else:
            os.unlink(path)
        log("ending")
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_ln(q, identifier, pointTo, symlink):
    log(f'handle_file_ln {pointTo} {symlink}')
    try:
        os.symlink(pointTo, symlink)
        send_remote_file(q, symlink)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, symlink)

async def handle_file_mv(q, identifier, source, dest):
    log(f'handle_file_mv {source} {dest}')
    try:
        shutil.move(source, dest)
        send_remote_file(q, dest)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, source)

async def handle_file_mkdir(q, identifier, path):
    log(f'handle_file_mkdir {identifier} {path}')
    try:
        os.mkdir(path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_create(q, identifier, path, content):
    log(f'handle_file_create {identifier} {path} length={len(content)} bytes')
    try:
        with open(path, "wb") as f:
            f.write(content)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_append(q, identifier, path, content):
    log(f'handle_file_append {identifier} {path} length={len(content)} bytes')
    try:
        with open(path, "ab") as f:
            f.write(content)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_utime(q, identifier, path, date):
    log(f'handle_file_utime {identifier} {path} {date}')
    try:
        os.utime(path, (date, date))
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_file_chmod_u(q, identifier, path, mode):
    log(f'handle_file_chmod_u {identifier} {path} {mode}')
    try:
        s = os.stat(path, follow_symlinks=False)
        value = s.st_mode & ~(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        if "r" in mode:
            value |= stat.S_IRUSR
        if "w" in mode:
            value |= stat.S_IWUSR
        if "x" in mode:
            value |= stat.S_IXUSR
        os.chmod(path, value)
        send_remote_file(q, path)
        end(q, identifier, 0)
    except Exception as e:
        file_error(q, identifier, e, path)

async def handle_recover(identifier, args):
    log("handle_recover")
    q = lock()
    # Keep this section await-free through unlock(q): the begin-recovery..end-recovery
    # block must stay contiguous. _it2_close_connections() aborts orphaned it2 connections
    # whose reader coroutines emit a `%it2 close` in their finally; abort() defers that via
    # call_soon so it runs only after we return, but a stray await here could let a woken
    # reader interleave that line into the recovery block.
    reset()
    _it2_close_connections()
    FLOW.recover()
    flow_changed()
    send_esc(q, f'begin-recovery')
    send_esc(q, f'recovery: version 2')
    if FLOW.enabled:
        # The end of this block doubles as a drain's reply: everything before it is backlog.
        send_esc(q, f'recovery: flow {FLOW.version} {FLOW_CLOCK_NAME}')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        if proc.login:
            send_esc(q, f'recovery: login {pid}')
            for key in RECOVERY_STATE:
                send_esc(q, f'recovery: {key} {RECOVERY_STATE[key]}')
        elif proc.pane:
            send_esc(q, f'recovery: pane {pid}')
        else:
            send_esc(q, f'recovery: process {pid}')
    send_esc(q, f'end-recovery')
    unlock(q)

async def handle_register(identifier, args):
    if len(args) < 1:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
    except Exception as e:
        log(f'handle_register: {e}')
        fail(identifier, "exception decoding argument")
        return
    q = begin(identifier)
    end(q,identifier, 0)
    await register(pid)

async def handle_deregister(identifier, args):
    if len(args) < 1:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
    except Exception as e:
        log(f'handle_deregister: {e}')
        fail(identifier, "exception decoding argument")
        return
    q = begin(identifier)
    end(q,identifier, 0)
    await deregister(pid)

async def handle_autopoll(identifier, args):
    log(f'handle_autopoll({identifier}, {args})')
    q = begin(identifier)
    end(q,identifier, 0)
    global AUTOPOLL
    if AUTOPOLL:
        return
    AUTOPOLL = 1

    global AUTOPOLL_TASK
    if AUTOPOLL_TASK is not None:
        return
    AUTOPOLL_TASK = asyncio.create_task(autopoll(1.0))

async def handle_poll(identifier, args):
    log(f'handle_poll({identifier}, {args})')
    output = await poll()
    q = begin(identifier)
    if output is not None:
        log(f'handle_poll({identifier}, {args}): read {len(output)} categories of output')
        # A reply's lines must each be a frame; iTerm2 leaves the protocol on raw text there.
        for line in poll_output_lines(output):
            send_esc(q, line)
        end(q,identifier, 0)
    else:
        end(q,identifier, 1)

async def handle_send(identifier, args):
    if len(args) < 2:
        fail(identifier, "not enough arguments")
        return
    try:
        pid = int(args[0])
        decoded = base64.b64decode(args[1])
    except Exception as e:
        log(f'handle_send: {e}')
        fail(identifier, "exception decoding argument")
        return
    if pid not in PROCESSES:
        log("No such process")
        q = begin(identifier)
        end(q,identifier, 1)
        return
    proc = PROCESSES[pid]
    log(f'write {decoded}')
    await proc.write(decoded)
    log('wrote')
    q = begin(identifier)
    end(q,identifier, 0)
    return False

async def handle_kill(identifier, args):
    """kill <pid> [hup]: end a process. A pane is hung up on, as closing a terminal does; any
    other process gets SIGTERM, or with `hup` is hung up on too, which ends an interactive shell
    that ignores SIGTERM. A framer before `hup` ignores it and sends SIGTERM."""
    log(f'kill {args}')
    try:
        pid = int(args[0])
    except:
        fail(identifier, "pid not an int")
        return
    if pid not in PROCESSES:
        log(f'no such process')
        q = begin(identifier)
        end(q,identifier, 1)
        return
    proc = PROCESSES[int(args[0])]
    if proc.pane or args[1:2] == ["hup"]:
        proc.hang_up()
    else:
        proc.send_signal(signal.SIGTERM)
    q = begin(identifier)
    end(q,identifier, 0)
    return False

async def handle_flow(identifier, args):
    """flow on [version]: turn flow control on with the initial credit, speaking `version`
    (1 if omitted). Answers with that version and the clock that %output timestamps use.
    iTerm2 must not grant until it has the answer. (A grant is a command too, but
    command_reader applies it as soon as it is read and it gets no reply.)"""
    try:
        if not args or args[0] != "on" or len(args) > 2:
            raise ValueError(args)
        version = int(args[1]) if len(args) == 2 else 1
        if not 1 <= version <= FLOW_VERSION:
            raise ValueError(version)
    except ValueError:
        fail(identifier, "bad arguments")
        return False
    FLOW.enable(version)
    flow_changed()
    q = begin(identifier)
    send_esc(q, f'{version} {FLOW_CLOCK_NAME}')
    end(q, identifier, 0)
    return False

async def handle_drain(identifier, args):
    """Zero the credit and hold output (it2 data too) until the next grant. The reply
    follows everything sent before it, so its arrival tells iTerm2 the path is empty."""
    FLOW.drain()
    flow_changed()
    q = begin(identifier)
    end(q, identifier, 0)
    return False

async def handle_ping(identifier, args):
    """Answers at once. Sent after a drain to time a round trip across an empty path."""
    q = begin(identifier)
    end(q, identifier, 0)
    return False

async def handle_quit(identifier, args):
    q = begin(identifier)
    end(q,identifier, 0)
    global AUTOPOLL_TASK
    if AUTOPOLL_TASK:
        log('will cancel autopoll')
        AUTOPOLL_TASK.cancel()
        try:
            log('await canceled autopoll task')
            await AUTOPOLL_TASK
        except asyncio.CancelledError:
            log('autopoll is now canceled')
        AUTOPOLL_TASK = None
    _it2_teardown_socket()
    cancel_search()
    return True

def cancel_search():
    global SEARCH_TASK
    if SEARCH_TASK:
        SEARCH_TASK.cancel()
        SEARCH_TASK = None

## Helpers for run()

async def start_process(args):
    runid = makeid()
    PROCESSES[runid] = proc
    return runid

def make_monitor_process(proc, islogin):
    def monitor_process(channel, value, exempt=False):
        log(f'monitor_process called with channel={channel} islogin={islogin} value={value}')
        if len(value) == 0:
            global COMPLETED
            log(f'add {proc.pid} to list of completed PIDs')
            COMPLETED.append(proc.pid)
            return cleanup()
        if proc.pane:
            # iTerm2 reads a pane's terminal modes from the pane's own session, and the
            # %notif tty report names no process, so it would be taken as the leader's.
            print_output(makeid(), proc.pid, PANE_CHANNEL, False, value, exempt, flow=proc.pid)
            return None
        print_output(makeid(), proc.pid, channel, islogin, value, exempt)
        log("make_monitor_process: poll")
        try:
            poll_tty(proc)
        except Exception as e:
            log(f'make_monitor_process->poll_tty threw {e}: {traceback.format_exc()}')
        return None
    return monitor_process

def flow_suffix(flow, exempt=False):
    """Under flow control, the framer's clock (for iTerm2's one-way delay) and the flags."""
    if not FLOW.controls(flow):
        return ''
    return f' {flow_send_ms()} {FLOW.take_flags(exempt, flow)}'

def print_output(identifier, pid, channel, islogin, data, exempt=False, flow=FLOW_LEADER):
    q = lock()
    if islogin:
        channel = -1
    send_esc(q, f'%output {identifier} {pid} {channel} {DEPTH}{flow_suffix(flow, exempt)}')
    send(q, data)
    send_esc(q, f'%end {identifier}')
    unlock(q)

def print_tty(message):
    q = lock()
    send_esc(q, f'%notif tty {message}')
    unlock(q)

## Infra

def fail(identifier, reason):
    log(f'fail: {reason}')
    q = begin(identifier)
    end(q, identifier, 1)

def begin(identifier):
    q = lock()
    send_esc(q, f'begin {identifier}')
    return q

def end(q, identifier, status):
    if len(PROCESSES):
        type = "f"
    else:
        type = "r"
    send_esc(q, f'end {identifier} {status} {type}')
    REPLIED.add(identifier)
    unlock(q)

async def cleanup():
    """Await tasks that have completed, clear the COMPLETED list, and remove them from TASKS."""
    log("cleaning up")
    global COMPLETED
    completed = list(COMPLETED)
    COMPLETED = []
    for pid in completed:
        if pid not in PROCESSES:
            log(f'pid {pid} no longer in PROCESSES, not cleaning up')
            continue
        log(f'clean up pid {pid}')
        proc = PROCESSES[pid]
        del PROCESSES[pid]
        if proc.pane:
            FLOW.forget(proc.pid)
        await proc.cleanup()
        q = lock()
        send_esc(q, f'%terminate {proc.pid} {proc.return_code}')
        unlock(q)

async def handle(args):
    log(f'handle {args}')
    if len(args) == 0:
        # During recovery a blank line is sent. Just ignore it to avoid getting out of sync.
        return False
    cmd = args[0]
    del args[0]
    identifier = makeid()
    if cmd not in HANDLERS:
        fail(identifier, "unrecognized command")
        return

    f = HANDLERS[cmd]
    log(f'handler is {f}')
    should_quit = False
    try:
        should_quit = await f(identifier, args)
        if should_quit:
            global QUITTING
            QUITTING=True
    except Exception as e:
        log(f'Handler for {cmd} threw {e}: {traceback.format_exc()}')
        if identifier not in REPLIED:
            # Whatever the handler queued is lost; without a reply iTerm2 would wait forever.
            fail(identifier, f'{cmd} threw {e}')
    REPLIED.discard(identifier)
    log("call cleanup()")
    await cleanup()

    global TASKS
    log(f'awaiting {TASKS}')
    while TASKS:
        task = TASKS[0]
        del TASKS[0]
        log(f'await {task}')
        await task
    TASKS=[]

    return should_quit

async def mainloop():
    global RUNLOOP
    RUNLOOP = asyncio.get_event_loop()
    commands = asyncio.Queue()
    threading.Thread(target=command_reader, args=(sys.stdin, RUNLOOP, commands),
                     daemon=True).start()
    args = []
    while True:
        log("reading")
        try:
            line = await commands.get()
        except:
            log("Exception while reading: " + traceback.format_exc())
            fail("none", "exception during read_line")
            return 0
        if line is None:
            log("End of input")
            cancel_search()
            return 0
        log(f'read from stdin "{line}" with length {len(line)}')
        if len(line):
            if len(args) and args[-1].endswith("\\"):
                args[-1] = args[-1][:-1] + line
            else:
                args.append(line)
            log(f'args is now {args}')
        else:
            try:
                args = [base64.b64decode(s).decode('utf-8') for s in args]
            except ValueError as e:
                # binascii.Error and UnicodeDecodeError are both ValueErrors. Answer so iTerm2
                # stays in step: it expects one reply per command.
                log(f'Malformed command: {e}')
                fail(makeid(), "malformed command")
                args = []
                continue
            quit = await handle(args)
            log("flush stdout")
            sys.stdout.flush()
            if quit:
                log("Mainloop returns 0")
                return 0
            args = []

def ping():
    if len(PROCESSES):
        q = lock()
        send_esc(q, "%ping")
        unlock(q)
    else:
        log("Squelch pre-login ping")

async def update_pty_size():
    log(f'update_pty_size')
    window_size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, '00000000')
    for pid in PROCESSES:
        proc = PROCESSES[pid]
        if proc.pane:
            # A pane has its own size; iTerm2 sets it with panesize.
            continue
        master = proc.master
        if master is not None:
            log(f'TIOCSWINSZ {proc}')
            # TODO: This is wrong becuse it could happen while awaiting something else between begin and end.
            fcntl.ioctl(master, termios.TIOCSWINSZ, window_size)
        else:
            log(f'no master fd for {proc}')

def on_sigwinch(_sig, _stack):
    log(f'Received SIGWINCH')
    if RUNLOOP is None:
        # There may not be an event loop yet.
        log('Ignore because no runloop')
        return
    # A signal handler can run between any two bytecodes, including in the middle of
    # writing a frame or a command's reply, so it must not write. The event loop runs
    # the ping between callbacks, and every write finishes within a single callback.
    RUNLOOP.call_soon_threadsafe(ping)
    asyncio.run_coroutine_threadsafe(update_pty_size(), RUNLOOP)

# it2-over-ssh: proxy a remote unix socket to iTerm2. iTerm2's embedded it2 runs
# the command; framer.py is a dumb byte pipe. Frames up: "%it2 <connid> open",
# "%it2 <connid> data <base64>", "%it2 <connid> close". Commands down: "it2send
# <connid> <base64>", "it2close <connid>".
def _it2_teardown_socket():
    """Close the it2 server, unlink its socket, and release+remove its liveness lock, and
    the /tmp directory it was in if it had one of its own. Idempotent and safe from atexit;
    everything lives in a persistent per-user dir so a leak would linger."""
    global IT2_SERVER, IT2_SOCKET_PATH, IT2_LOCK_FD, IT2_LOCK_PATH, IT2_SOCKET_TMPDIR
    if IT2_SERVER is not None:
        with contextlib.suppress(Exception):
            IT2_SERVER.close()
        IT2_SERVER = None
    if IT2_SOCKET_PATH is not None:
        with contextlib.suppress(OSError):
            os.unlink(IT2_SOCKET_PATH)
        IT2_SOCKET_PATH = None
    if IT2_LOCK_PATH is not None:
        with contextlib.suppress(OSError):
            os.unlink(IT2_LOCK_PATH)
        IT2_LOCK_PATH = None
    if IT2_LOCK_FD is not None:
        with contextlib.suppress(OSError):
            os.close(IT2_LOCK_FD)  # closing the fd drops the advisory lock
        IT2_LOCK_FD = None
    if IT2_SOCKET_TMPDIR is not None:
        with contextlib.suppress(OSError):
            os.rmdir(IT2_SOCKET_TMPDIR)
        IT2_SOCKET_TMPDIR = None

# Covers exits that skip handle_quit (read error, SIGHUP-then-clean-exit, etc.).
atexit.register(_it2_teardown_socket)

def _it2_remove_socket_files():
    """Remove the socket, its lock file and its /tmp directory, for a framer about to die of a
    signal, which skips atexit. Only unlinks: closing the server from a signal handler could
    land in the middle of the event loop, and the process is ending anyway."""
    for path in (IT2_SOCKET_PATH, IT2_LOCK_PATH):
        if path is not None:
            with contextlib.suppress(OSError):
                os.unlink(path)
    if IT2_SOCKET_TMPDIR is not None:
        with contextlib.suppress(OSError):
            os.rmdir(IT2_SOCKET_TMPDIR)

# The framer's own pid, so a signal that lands in a forked child before it execs (run_tty's
# preexec_fn runs Python there) does not remove the framer's live socket.
TERMINATING_SIGNAL_PID = None

def _on_terminating_signal(signum, frame):
    """A hangup (the ssh connection went away) or a termination: clean up, then die of the
    signal as before."""
    if os.getpid() == TERMINATING_SIGNAL_PID:
        _it2_remove_socket_files()
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)

def install_terminating_signal_handlers():
    """Clean up the it2 socket on SIGHUP and SIGTERM. A signal someone chose to ignore (nohup)
    stays ignored."""
    global TERMINATING_SIGNAL_PID
    TERMINATING_SIGNAL_PID = os.getpid()
    for sig in (signal.SIGHUP, signal.SIGTERM):
        if signal.getsignal(sig) == signal.SIG_DFL:
            signal.signal(sig, _on_terminating_signal)

def _it2_is_tmp_socket_dir(socket_dir):
    return (os.path.dirname(socket_dir) == IT2_TMP_SOCKET_ROOT and
            os.path.basename(socket_dir).startswith(IT2_TMP_SOCKET_PREFIX))

def _it2_sweep_stale_tmp_socket_dirs(keep_dir):
    """Remove /tmp/.it2-* directories of this user that no live framer uses, left by framers
    killed before they could clean up (SIGKILL, a crash). Each is swept like the socket
    directory itself, so a socket whose lock is held survives and keeps its directory; one
    then left empty goes, unless it is new enough that another framer may have just made it.
    Only real directories owned by this user, never through a symlink."""
    try:
        names = os.listdir(IT2_TMP_SOCKET_ROOT)
    except OSError:
        return
    uid = os.getuid()
    now = time.time()
    for name in names:
        if not name.startswith(IT2_TMP_SOCKET_PREFIX):
            continue
        full = os.path.join(IT2_TMP_SOCKET_ROOT, name)
        if full == keep_dir:
            continue
        try:
            st = os.lstat(full)
        except OSError:
            continue
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != uid:
            continue
        _it2_sweep_stale_sockets(full, keep=None)
        # The age from before the sweep, which itself touches the directory.
        if now - st.st_mtime < IT2_TMP_SOCKET_DIR_GRACE:
            continue
        with contextlib.suppress(OSError):
            os.rmdir(full)

def _it2_close_connections():
    """Abort every accepted it2 client connection (but keep the listening socket).
    Called on recovery: iTerm2 restarted/reattached, so the demux that owned these
    connections is gone and their commands can never complete. Aborting each writer
    gives the orphaned it2.py client an EOF/RST so it exits instead of blocking forever
    on recv (its socket stayed open because this framer survived the restart)."""
    global IT2_CONNS
    for writer in list(IT2_CONNS.values()):
        # abort(), not close(): a graceful close() waits for the send buffer to flush
        # before sending FIN, which never completes for a stalled follow-stream whose
        # client stopped reading (exactly the mid-send connection this must unblock).
        # abort() RSTs immediately so the orphaned it2.py gets EOF/error and exits.
        with contextlib.suppress(Exception):
            writer.transport.abort()
    IT2_CONNS = {}

def _it2_lock_path(sock_path):
    return sock_path + ".lock"


def _it2_lock_is_held(lock_path):
    """True iff some live framer currently holds the exclusive advisory lock on lock_path.
    We test it non-blocking by trying to take it and dropping it immediately (closing the fd
    releases our test lock; a real owner's lock lives on a different fd and is untouched). A
    missing lock file is not held. An unopenable one is treated as held, i.e. we keep the
    socket rather than risk reclaiming a live one."""
    try:
        fd = os.open(lock_path, os.O_RDWR)
    except FileNotFoundError:
        return False
    except OSError:
        return True
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return False  # acquired -> nobody holds it
    except OSError:
        return True   # a live framer holds it
    finally:
        os.close(fd)


def _it2_sweep_stale_sockets(socket_dir, keep):
    """Reclaim it2 sockets leaked by prior sessions. When an ssh connection drops, framer is
    killed (SIGHUP/SIGKILL) before handle_quit or the atexit hook can unlink its socket, and
    each session used a fresh random name, so the owner-only dir accumulates dead sockets.
    Validity is decided by the liveness lock, not by connecting: the owner holds an exclusive
    flock on <socket>.lock for its whole life and the kernel drops it on death, so a socket
    whose lock is not held (dead owner) -- or has no lock at all (a leftover predating this
    scheme, e.g. the sockets already piled up on a host) -- is stale and reclaimable, while a
    held lock proves a live owner. Unlike a connect probe this cannot race a bind-in-progress
    or disturb a live peer. `keep` (the path we are about to bind) is skipped."""
    try:
        names = os.listdir(socket_dir)
    except OSError:
        return
    for name in names:
        full = os.path.join(socket_dir, name)
        if name.endswith(".sock") and full != keep:
            # Stale iff no live owner holds its lock (or there is no lock sidecar at all).
            if not _it2_lock_is_held(_it2_lock_path(full)):
                with contextlib.suppress(OSError):
                    os.unlink(full)
                with contextlib.suppress(OSError):
                    os.unlink(_it2_lock_path(full))
        elif name.endswith(".sock.lock") and (keep is None or full != _it2_lock_path(keep)):
            # An orphan lock whose socket is already gone (owner died between locking and
            # binding, or after its socket was reclaimed above): drop it if unheld.
            sock_path = full[: -len(".lock")]
            if not os.path.exists(sock_path) and not _it2_lock_is_held(full):
                with contextlib.suppress(OSError):
                    os.unlink(full)


async def handle_it2listen(identifier, args):
    q = begin(identifier)
    global IT2_SERVER
    if IT2_SERVER is not None:
        end(q, identifier, 0)
        return
    if not args:
        end(q, identifier, 1)
        return
    path = args[0]
    global IT2_SOCKET_PATH, IT2_LOCK_FD, IT2_LOCK_PATH, IT2_SOCKET_TMPDIR
    try:
        # Contain the socket in an owner-only (0700) directory. The socket file
        # itself is created 0700 (umask) then chmod 0600, but bind-time socket
        # permissions are not portable across platforms, so a 0700 parent is the
        # authoritative guard: no other local user can traverse to the socket to
        # connect to it, and none can pre-create/substitute it (this dir is under
        # $HOME, which only the owner can write). chmod fixes a pre-existing dir.
        socket_dir = os.path.dirname(path)
        if socket_dir:
            os.makedirs(socket_dir, mode=0o700, exist_ok=True)
            if _it2_is_tmp_socket_dir(socket_dir):
                # In /tmp anyone can create a name first. Use it only if it is a real
                # directory of this user's, not a symlink or someone else's.
                st = os.lstat(socket_dir)
                if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
                    raise OSError("%s is not a directory of this user's" % socket_dir)
            os.chmod(socket_dir, stat.S_IRWXU)
            # Reclaim sockets leaked by prior sessions killed before they could clean up.
            _it2_sweep_stale_sockets(socket_dir, keep=path)
            if _it2_is_tmp_socket_dir(socket_dir):
                IT2_SOCKET_TMPDIR = socket_dir
                _it2_sweep_stale_tmp_socket_dirs(keep_dir=socket_dir)
        # Take the liveness lock BEFORE binding, so a concurrent sweeper always sees a live
        # owner for this socket and never reclaims it mid-bind. Held for our whole lifetime
        # via IT2_LOCK_FD; released by the kernel if we are killed. LOCK_NB fails only if
        # another live framer already owns this exact (random) path, which cannot happen in
        # practice -- treat it as a hard failure rather than blocking.
        lock_path = _it2_lock_path(path)
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(lock_fd)
            raise
        IT2_LOCK_FD = lock_fd
        IT2_LOCK_PATH = lock_path
        try:
            os.unlink(path)
        except OSError:
            pass
        # Bind under an owner-only umask so the socket is created as 0700 with no
        # window during which another local user could connect; the chmod then
        # narrows it to 0600 as belt-and-suspenders. umask only ever makes files
        # more restrictive, so leaking it to a concurrent task is harmless.
        old_umask = os.umask(0o077)
        try:
            IT2_SERVER = await asyncio.start_unix_server(handle_it2_connection, path=path)
        finally:
            os.umask(old_umask)
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        IT2_SOCKET_PATH = path
        end(q, identifier, 0)
    except Exception as e:
        log(f'handle_it2listen failed: {e}')
        # Do not leave a live, possibly non-owner-restricted socket behind after
        # reporting failure: tear down whatever start_unix_server created and
        # reset the global so a later it2listen can retry instead of no-opping.
        if IT2_SERVER is not None:
            with contextlib.suppress(Exception):
                IT2_SERVER.close()
            IT2_SERVER = None
        IT2_SOCKET_PATH = None
        with contextlib.suppress(OSError):
            os.unlink(path)
        # Release + remove the liveness lock if we took it before the failure.
        if IT2_LOCK_FD is not None:
            with contextlib.suppress(OSError):
                os.close(IT2_LOCK_FD)
            IT2_LOCK_FD = None
        with contextlib.suppress(OSError):
            os.unlink(_it2_lock_path(path))
        IT2_LOCK_PATH = None
        if IT2_SOCKET_TMPDIR is not None:
            with contextlib.suppress(OSError):
                os.rmdir(IT2_SOCKET_TMPDIR)
            IT2_SOCKET_TMPDIR = None
        end(q, identifier, 1)

async def handle_it2_connection(reader, writer):
    connid = makeid()
    # Register and emit `open` INSIDE the try, so that if the `open` emission (unlock's
    # os.write to the ssh up-channel) raises -- e.g. iTerm2's read side already closed --
    # the finally still pops IT2_CONNS and closes the writer instead of leaking both.
    try:
        IT2_CONNS[connid] = writer
        q = lock()
        send_esc(q, f'%it2 {connid} open')
        unlock(q)
        # A byte read while there was no credit, held until there is. Reading it is how the
        # end of the connection is noticed without credit, as with a pty's peek.
        held = b''
        while True:
            if not held and FLOW.controls(FLOW_IT2) and not it2_may_read():
                held = await reader.read(1)
                if not held:
                    break
            await it2_gate()
            if held:
                data, held = held, b''
            else:
                size = IT2_READ_CHUNK
                if FLOW.controls(FLOW_IT2):
                    size = min(size, max(1, FLOW.budget(FLOW_IT2)))
                data = await reader.read(size)
                if not data:
                    break
            FLOW.spend(len(data), FLOW_IT2)
            q = lock()
            send_esc(q, f'%it2 {connid} data {base64.b64encode(data).decode("ascii")}{flow_suffix(FLOW_IT2)}')
            unlock(q)
            if FLOW.controls(FLOW_IT2):
                flow_changed()
    except Exception as e:
        log(f'it2 connection {connid}: {e}')
    finally:
        IT2_CONNS.pop(connid, None)
        # Emit `close` UNLESS iTerm2 itself initiated the teardown via it2close (then it already
        # forgot the connid and a close echo would be a duplicate/unsolicited frame). A
        # framer/client-initiated teardown -- client disconnect, or a buffer-cap abort that
        # popped connid -- is NOT flagged here, so it still emits close so iTerm2 learns the
        # connection died. Suppress() so a failing close emission cannot skip writer.close().
        locally_closed = connid in IT2_LOCALLY_CLOSED
        IT2_LOCALLY_CLOSED.discard(connid)
        if not locally_closed:
            with contextlib.suppress(Exception):
                q = lock()
                send_esc(q, f'%it2 {connid} close')
                unlock(q)
        with contextlib.suppress(Exception):
            writer.close()

async def handle_it2send(identifier, args):
    q = begin(identifier)
    if len(args) < 2 or args[0] not in IT2_CONNS:
        end(q, identifier, 1)
        return
    writer = IT2_CONNS[args[0]]
    # Sample the unsent buffer BEFORE writing. The cap guards against a *stalled* consumer
    # whose buffer grows without bound across successive sends; a single frame onto a healthy
    # (near-empty) buffer is bounded memory, not a leak, so it must pass even if it alone
    # exceeds the cap. Sampling AFTER the write would abort a perfectly healthy fast client on
    # one oversized down-frame: write() does a single optimistic synchronous send (bounded by
    # the ~200 KB socket wmem) and buffers the rest, and there is no await before the sample,
    # so the event loop never runs to flush first -> the whole frame reads as over-cap. A
    # genuinely wedged consumer is still caught on its NEXT send, when the accumulated unsent
    # buffer is over the cap before we even write.
    try:
        buffered = writer.transport.get_write_buffer_size()
    except Exception:
        buffered = 0
    if buffered > IT2_WRITE_BUFFER_MAX:
        log(f'handle_it2send: write buffer {buffered} over cap for {args[0]}; dropping connection')
        IT2_CONNS.pop(args[0], None)
        with contextlib.suppress(Exception):
            writer.transport.abort()
        end(q, identifier, 1)
        return
    # Decode OUTSIDE the socket try/except: a malformed base64 payload (bad padding, a
    # corrupted/truncated command line) raises binascii.Error/ValueError, which is NOT a dead
    # socket. Skip just this frame and keep the connection alive rather than tearing it down
    # (pop+abort) the way a genuine write failure must.
    try:
        payload = base64.b64decode(args[1])
    except (ValueError, TypeError) as e:
        log(f'handle_it2send: bad base64 for {args[0]}: {e}; dropping this frame')
        end(q, identifier, 1)
        return
    try:
        writer.write(payload)
    except Exception as e:
        # A write failure (e.g. the peer RST'd the socket mid-stream ->
        # ConnectionResetError/BrokenPipeError) leaves a dead writer. Drop and abort it so
        # later sends do not re-enter and repeat the failing write.
        log(f'handle_it2send: {e}')
        IT2_CONNS.pop(args[0], None)
        with contextlib.suppress(Exception):
            writer.transport.abort()
        end(q, identifier, 1)
        return
    # Do NOT await drain() here. This is the single serial command loop (mainloop does
    # `await handle(args)` and reads no further command until it returns), so blocking on a
    # stalled consumer's backpressure would freeze send/kill/file/poll for the WHOLE ssh
    # session. write() only buffers; asyncio flushes it in the background as the socket
    # drains, so a live-but-slow consumer keeps working.
    end(q, identifier, 0)

async def handle_it2close(identifier, args):
    q = begin(identifier)
    connid = args[0] if args else None
    writer = IT2_CONNS.pop(connid, None) if connid is not None else None
    if writer is not None:
        # Flag this as an iTerm2-initiated close so the still-live reader coroutine's finally
        # does not echo a duplicate close back up. Only meaningful while the reader is alive
        # (connid was still registered); it discards the flag when it unwinds.
        IT2_LOCALLY_CLOSED.add(connid)
        # abort(), not close(): a graceful close() defers FIN until the send buffer flushes,
        # which never happens for a stalled follow-stream client (paused stdout consumer, so the
        # down buffer is non-empty). That would leave the socket fd open, the reader coroutine
        # blocked on read() forever, and its IT2_LOCALLY_CLOSED flag leaked for the ssh
        # session's life. abort() RSTs immediately, giving the reader EOF so it unwinds. Matches
        # the twin _it2_close_connections().
        with contextlib.suppress(Exception):
            writer.transport.abort()
    end(q, identifier, 0)


HANDLERS = {
    "run": handle_run,
    "login": handle_login,
    "pane": handle_pane,
    "panesize": handle_panesize,
    "panes": handle_panes,
    "send": handle_send,
    "kill": handle_kill,
    "quit": handle_quit,
    "register": handle_register,
    "deregister": handle_deregister,
    "poll": handle_poll,
    "reset": handle_reset1,
    "reset2": handle_reset2,
    "autopoll": handle_autopoll,
    "recover": handle_recover,
    "save": handle_save,
    "file": handle_file,
    "eval": handle_eval,
    "getenv": handle_getenv,
    "runpy": handle_runpy,
    "it2listen": handle_it2listen,
    "it2send": handle_it2send,
    "it2close": handle_it2close,
    "flow": handle_flow,
    "drain": handle_drain,
    "ping": handle_ping
}

def _silence_shutdown_unraisable(unraisable):
    # Subprocess transports' __del__ runs after asyncio.run() has closed the
    # loop; their cleanup calls call_soon() and raises "Event loop is closed".
    # We're on our way out — nobody cares.
    exc = unraisable.exc_value
    if isinstance(exc, RuntimeError) and 'Event loop is closed' in str(exc):
        return
    sys.__unraisablehook__(unraisable)

def main():
    claim_put_bin_flag()
    install_terminating_signal_handlers()
    if sys.stdin.isatty():
        signal.signal(signal.SIGWINCH, on_sigwinch)
    sys.unraisablehook = _silence_shutdown_unraisable
    try:
        asyncio.run(mainloop())
    except Exception as e:
        log(f'Exception {traceback.format_exc()}')

if __name__ == "__main__":
    main()
