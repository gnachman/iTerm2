#!/usr/bin/env python3
"""Shared harness for framer.py tests.

framer.py runs on a remote host. iTerm2 talks to it over ssh: commands go down as lines of
base64 (one argument per line, a trailing backslash continues an argument, a blank line ends
the command) and everything comes back up in OSC 134 frames. This module provides:

  * load_framer() and reset_framer(): import framer.py in-process (as framer_flow_test.py
    does) and forget every global that would otherwise leak from one asyncio.run() to the next.
  * FrameParser: a port of iTerm2's VT100ConductorParser (sources/VT100/VT100ConductorParser.swift)
    that turns the byte stream into replies, %output blocks and notifications, and records
    anything iTerm2 would unhook on.
  * InProcess and FramerTestCase: run handlers in-process and collect what they write.
  * encode_command() and FramerProcess: speak the real wire protocol to
    `python3 framer.py` running on a pty, the way Conductor.swift does over ssh.

Not a test file itself. Run the suite with tools/run_framer_tests.sh.
"""
import asyncio
import atexit
import base64
import contextlib
import fcntl
import importlib.util
import os
import pty
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
FRAMER_PATH = os.path.join(REPO, "OtherResources", "framer.py")

# A shell starts background jobs with SIGINT ignored, and an ignored signal stays ignored
# across fork and exec, so the framer's programs would not die of ^C. Restore the default so
# the tests behave the same however they were started.
signal.signal(signal.SIGINT, signal.default_int_handler)

# Generous: a slow or loaded machine must not fail a test. Only a hang waits this long.
TIMEOUT = 30.0

ESC = 0x1b


def scratch_dir(prefix="framer-test-"):
    """A fresh real-path temporary directory. FRAMER_TEST_TMPDIR picks the parent."""
    parent = os.environ.get("FRAMER_TEST_TMPDIR") or None
    if parent:
        os.makedirs(parent, exist_ok=True)
    return os.path.realpath(tempfile.mkdtemp(prefix=prefix, dir=parent))


def b64(value):
    """Base64 of a str (as UTF-8) or bytes, as a str."""
    if isinstance(value, str):
        value = value.encode("utf-8")
    return base64.b64encode(value).decode("ascii")


## Loading the framer in-process

def load_framer(module_name="framer_under_test"):
    spec = importlib.util.spec_from_file_location(module_name, FRAMER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # Conductor.swift replaces "#{SUB}" with this before sending the framer.
    module.DEPTH = 0
    return module


def reset_framer(framer):
    """Forget state from the previous test. Each test runs its own event loop, so timers,
    tasks and events that belonged to the last one must go."""
    framer.PROCESSES.clear()
    framer.COMPLETED = []
    framer.TASKS = []
    framer.QUITTING = False
    framer.REPLIED = set()
    framer.REGISTERED = []
    framer.LASTPS = {}
    framer.AUTOPOLL = 0
    framer.AUTOPOLL_TASK = None
    framer.TTY_TASK = None
    framer.RECOVERY_STATE = {}
    framer.RUNLOOP = None
    if framer.SEARCH_TASK is not None:
        with contextlib.suppress(Exception):
            framer.SEARCH_TASK.cancel()
    framer.SEARCH_TASK = None
    framer.FLOW = framer.FlowControl(framer.flow_now)
    framer.SOURCES.clear()
    framer.PUMP_SCHEDULED = False
    framer.PUMP_ROTATION = 0
    framer.PUMP_TASKS.clear()
    framer.FLOW_TICK_HANDLE = None
    framer.ECHO_TIMER = None
    framer.IT2_GATE = None
    framer._it2_teardown_socket()
    framer.IT2_CONNS = {}
    framer.IT2_LOCALLY_CLOSED.clear()
    framer.mpstat_exists = None


## iTerm2's parser

class Reply:
    def __init__(self, identifier, lines, status, kind):
        self.id = identifier
        self.lines = lines
        self.status = status
        # "f" while the framer has processes, else "r".
        self.kind = kind

    def __repr__(self):
        return "Reply(%r, %r, status=%r, %r)" % (self.id, self.lines, self.status, self.kind)


class Output:
    def __init__(self, flavor, header, data):
        self.flavor = flavor            # "%output" or "%autopoll"
        self.header = header            # the header split on spaces
        self.id = header[1]
        self.data = bytes(data)
        if flavor == "%output":
            self.pid = int(header[2])
            self.channel = int(header[3])
            self.depth = int(header[4])
        else:
            self.pid = self.channel = self.depth = None

    def __repr__(self):
        return "Output(%r, %r)" % (" ".join(self.header), self.data)


class Event:
    """A one-frame event: kind is notif, terminate, it2, ignored (an unknown %-notification
    such as %ping) or recovery (a line iTerm2 accepts only in recovery mode)."""

    def __init__(self, kind, text):
        self.kind = kind
        self.text = text

    @property
    def parts(self):
        return self.text.split(" ")

    def __repr__(self):
        return "Event(%r, %r)" % (self.kind, self.text)


class FrameParser:
    """Port of VT100ConductorParser's ground, body and output states. Feed it bytes; it
    appends Reply, Output and Event objects to `events`. Anything that would make iTerm2
    unhook goes in `errors` and stops parsing, as it would in iTerm2."""

    def __init__(self, recovery_mode=False):
        self.buf = bytearray()
        self.pos = 0
        self.state = "ground"
        self.body_id = None
        self.body_lines = []
        self.builder = None   # (flavor, header, bytearray) while in the output state
        self.recovery_mode = recovery_mode
        self.events = []
        self.errors = []
        self.unhooked = False

    def feed(self, data):
        self.buf += data
        while not self.unhooked and self._step():
            pass
        if self.pos > 65536:
            del self.buf[:self.pos]
            self.pos = 0

    # parseNextOSC. Returns ("osc", code, payload), ("notosc",) or ("blocked",) and moves
    # self.pos as the Swift code moves the parser context.
    def _next_osc(self, skip_garbage):
        buf = self.buf
        i = self.pos
        checkpoint = i
        state = "ground"
        param = b""
        code = None
        payload = bytearray()
        while i < len(buf):
            c = buf[i]
            i += 1
            if state == "ground":
                if c == ESC:
                    state = "esc"
                else:
                    if not skip_garbage:
                        return ("notosc",)
                    checkpoint = i
            elif state == "esc":
                if c == ord("]"):
                    state = "osc"
                    param = b""
                else:
                    if not skip_garbage:
                        return ("notosc",)
                    state = "ground"
                    checkpoint = i
            elif state == "osc":
                if ord("0") <= c <= ord("9"):
                    param += bytes([c])
                elif c == ord(";") and param:
                    code = int(param)
                    payload = bytearray()
                    state = "param"
                else:
                    if not skip_garbage:
                        return ("notosc",)
                    state = "ground"
                    checkpoint = i
            elif state == "param":
                if c == ESC:
                    state = "oscesc"
                else:
                    payload.append(c)
            elif state == "oscesc":
                if c == ord("\\"):
                    self.pos = i
                    # As VT100ConductorParser reads it: UTF-8, or Latin-1 when it is not.
                    try:
                        text = payload.decode("utf-8")
                    except UnicodeDecodeError:
                        text = payload.decode("latin-1")
                    colon = text.find(":")
                    return ("osc", code, text[colon + 1:] if colon >= 0 else "")
                if not skip_garbage:
                    return ("notosc",)
                # An OSC interrupted by another: back up one and re-parse.
                i -= 1
                state = "ground"
                checkpoint = i
        self.pos = checkpoint
        return ("blocked",)

    def _unhook(self, why):
        self.errors.append(why)
        self.unhooked = True
        return False

    def _step(self):
        if self.state == "ground":
            return self._ground()
        if self.state == "body":
            return self._body()
        return self._output()

    def _ground(self):
        while self.pos < len(self.buf):
            result = self._next_osc(True)
            if result[0] == "blocked":
                return False
            if result[0] == "osc" and result[1] == 134:
                return self._framer_payload(result[2])
            if result[0] == "osc" and result[1] == 135:
                return self._unhook("pre-framer payload: %r" % result[2])
        return False

    def _framer_payload(self, s):
        was_recovery = self.recovery_mode
        self.recovery_mode = False
        if s.startswith("begin "):
            parts = s.split(" ")
            self.state = "body"
            self.body_id = parts[1]
            self.body_lines = []
            return True
        if s.startswith("%output ") or s.startswith("%autopoll ") or s.startswith("%notif "):
            parts = s.split(" ")
            flavor = parts[0]
            if flavor == "%notif":
                self.events.append(Event("notif", s[len("%notif "):]))
                return True
            if flavor == "%output":
                try:
                    pid, channel, _depth = int(parts[2]), int(parts[3]), int(parts[4])
                    ok = -2**31 <= pid < 2**31 and -128 <= channel < 128
                except (IndexError, ValueError):
                    ok = False
                if not ok:
                    return self._unhook("malformed %%output: %r" % s)
            self.state = "output"
            self.builder = (flavor, parts, bytearray())
            return True
        if s.startswith("%terminate "):
            parts = s.split(" ")
            try:
                int(parts[1])
                int(parts[2])
            except (IndexError, ValueError):
                return self._unhook("malformed %%terminate: %r" % s)
            self.events.append(Event("terminate", s[len("%terminate "):]))
            return True
        if s.startswith("%it2 "):
            if s[len("%it2 "):]:
                self.events.append(Event("it2", s[len("%it2 "):]))
            return True
        if s.startswith("%"):
            self.events.append(Event("ignored", s))
            return True
        if was_recovery:
            self.recovery_mode = True
            self.events.append(Event("recovery", s))
            return True
        return self._unhook("unrecognized payload in ground state: %r" % s)

    def _body(self):
        if self.pos >= len(self.buf):
            return False
        start = self.pos
        result = self._next_osc(False)
        if result[0] == "blocked":
            self.pos = start
            return False
        if result[0] == "osc" and result[1] in (134, 135):
            payload = result[2]
            prefix = "end %s " % self.body_id
            if payload.startswith(prefix):
                rest = payload[len(prefix):].split(" ")
                status = int(rest[0]) if rest and rest[0].lstrip("-").isdigit() else None
                kind = rest[1] if len(rest) > 1 else None
                self.events.append(Reply(self.body_id, self.body_lines, status, kind))
                self.state = "ground"
                return True
            self.body_lines.append(payload)
            return True
        self.pos = start
        return self._unhook("non-OSC 134 bytes inside reply %s: %r" %
                            (self.body_id, bytes(self.buf[start:start + 40])))

    def _output(self):
        flavor, header, data = self.builder
        start = self.pos
        result = self._next_osc(False)
        if result[0] == "osc" and result[1] == 134 and result[2] == "%end " + header[1]:
            self.events.append(Output(flavor, header, data))
            self.builder = None
            self.state = "ground"
            return True
        if result[0] == "blocked":
            self.pos = start
            return False
        # Not the terminator: consume up to the next ESC (at least one byte) as data.
        self.pos = start
        if self.pos >= len(self.buf):
            return False
        nxt = self.buf.find(b"\x1b", self.pos + 1) if self.buf[self.pos] == ESC else \
            self.buf.find(b"\x1b", self.pos)
        end = len(self.buf) if nxt < 0 else nxt
        data += self.buf[self.pos:end]
        self.pos = end
        return True

    # Queries

    def replies(self):
        return [e for e in self.events if isinstance(e, Reply)]

    def outputs(self, pid=None):
        return [e for e in self.events if isinstance(e, Output) and
                (pid is None or e.pid == pid)]

    def output_bytes(self, pid):
        return b"".join(o.data for o in self.outputs(pid))

    def notifications(self, kind=None):
        return [e for e in self.events if isinstance(e, Event) and
                (kind is None or e.kind == kind)]

    def terminate_status(self, pid):
        for e in self.notifications("terminate"):
            if int(e.parts[0]) == pid:
                return int(e.parts[1])
        return None


## In-process harness

_FRAMER = None


def shared_framer():
    """One framer module per test process, reset between tests."""
    global _FRAMER
    if _FRAMER is None:
        _FRAMER = load_framer()
    return _FRAMER


class InProcess:
    """Runs a framer module's handlers in-process. Everything the framer writes to stdout
    goes through _write_all, which is replaced so the bytes feed a FrameParser instead."""

    def __init__(self, framer):
        self.framer = framer
        self.parser = FrameParser()
        self.raw = bytearray()
        self.next_id = 0
        framer._write_all = self._write_all

    def _write_all(self, _fd, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        self.raw += data
        self.parser.feed(bytes(data))

    def new_id(self):
        self.next_id += 1
        return "t%d" % self.next_id

    def reply(self, identifier):
        for r in self.parser.replies():
            if r.id == identifier:
                return r
        return None

    async def command(self, *args):
        """Dispatch through framer.handle(), as mainloop does with decoded arguments, and
        return the reply it wrote (None if it wrote none)."""
        before = len(self.parser.replies())
        await self.framer.handle(list(args))
        after = self.parser.replies()
        return after[before] if len(after) > before else None

    async def call(self, handler, *args):
        """Call a handler directly with a known identifier and return its reply."""
        identifier = self.new_id()
        await handler(identifier, list(args))
        return self.reply(identifier)

    async def wait_for(self, predicate, timeout=TIMEOUT):
        loop = asyncio.get_event_loop()
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            if predicate():
                return True
            await asyncio.sleep(0.01)
        return predicate()

    async def start(self, *args):
        """Run a command that answers with a pid (run, login, eval, pane) and return the pid."""
        reply = await self.command(*args)
        assert reply is not None and reply.status == 0, (args, reply, self.parser.errors)
        return int(reply.lines[0])

    async def wait_terminated(self, pid, timeout=TIMEOUT):
        await self.wait_for(lambda: self.parser.terminate_status(pid) is not None, timeout)
        return self.parser.terminate_status(pid)

    async def finish(self):
        """Stop everything the test started, inside the test's own loop."""
        framer = self.framer
        if framer.SEARCH_TASK is not None:
            framer.SEARCH_TASK.cancel()
            with contextlib.suppress(BaseException):
                await asyncio.wait_for(framer.SEARCH_TASK.task, TIMEOUT)
            framer.SEARCH_TASK = None
        if framer.AUTOPOLL_TASK is not None:
            framer.AUTOPOLL_TASK.cancel()
            with contextlib.suppress(BaseException):
                await framer.AUTOPOLL_TASK
            framer.AUTOPOLL_TASK = None
        for proc in list(framer.PROCESSES.values()):
            task = getattr(proc, "tty_task", None)
            if task is not None:
                task.cancel()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(proc.cleanup(), TIMEOUT)
        framer.PROCESSES.clear()
        for task in list(framer.PUMP_TASKS):
            with contextlib.suppress(BaseException):
                await asyncio.wait_for(task, TIMEOUT)
        framer._it2_teardown_socket()
        for writer in list(framer.IT2_CONNS.values()):
            with contextlib.suppress(Exception):
                writer.transport.abort()
        framer.IT2_CONNS = {}


class FramerTestCase(unittest.TestCase):
    """Gives each test a reset framer (self.framer), an InProcess (self.h) and run_async()."""

    def setUp(self):
        self.framer = shared_framer()
        reset_framer(self.framer)
        self.h = InProcess(self.framer)
        self.tmp = scratch_dir()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        if os.path.exists(self.tmp):
            # A test may have removed its own permissions; put them back and retry.
            for root, dirs, _files in os.walk(self.tmp):
                for d in dirs:
                    with contextlib.suppress(OSError):
                        os.chmod(os.path.join(root, d), 0o700)
            shutil.rmtree(self.tmp, ignore_errors=True)

    def run_async(self, body):
        async def wrapper():
            self.framer.RUNLOOP = asyncio.get_running_loop()
            try:
                await body()
            finally:
                await self.h.finish()
        asyncio.run(wrapper())

    def assertNoParseErrors(self):
        self.assertEqual(self.h.parser.errors, [], bytes(self.h.raw[-400:]))


## The wire protocol

def chunk(s, size, continuation):
    """String.chunk(_:continuation:) from String+iTerm.swift."""
    parts = []
    i = 0
    while i < len(s):
        end = min(i + size, len(s))
        part = s[i:end] + (continuation if end < len(s) else "")
        if part:
            parts.append(part)
        i = end
    return parts


def encode_command(args, chunk_size=128):
    """What Conductor.encode(arguments:isFramer:linePrefix:) writes for a framer command
    (Conductor.swift), plus the newline write() adds: each argument base64-encoded ("=" when
    empty) and cut into chunk_size pieces that end in a backslash, one per line, and a blank
    line at the end."""
    lines = []
    for a in args:
        lines += chunk(b64(a) or "=", chunk_size, "\\")
    return ("\n".join(lines) + "\n" + "\n").encode("ascii")


_E2E_COPY = None


def framer_copy():
    """framer.py with #{SUB} replaced as Conductor.execFramer() does. The substitution is one
    line, so line numbers match the original (which lets coverage map the copy back)."""
    global _E2E_COPY
    if _E2E_COPY is None or not os.path.exists(_E2E_COPY):
        directory = os.path.join(scratch_dir("framer-e2e-"), "OtherResources")
        os.makedirs(directory)
        with open(FRAMER_PATH) as f:
            code = f.read().replace("#{SUB}", "DEPTH=0")
        _E2E_COPY = os.path.join(directory, "framer.py")
        atexit.register(shutil.rmtree, os.path.dirname(directory), True)
        with open(_E2E_COPY, "w") as f:
            f.write(code)
    return _E2E_COPY


def _python_command(script):
    if os.environ.get("FRAMER_E2E_COVERAGE"):
        return [sys.executable, "-m", "coverage", "run", "-p",
                "--include=*/OtherResources/framer.py", script]
    return [sys.executable, script]


class FramerProcess:
    """`python3 framer.py` on a pty, set up as conductor.sh leaves the remote tty
    (stty -echo -onlcr -opost -isig, canonical input), with the pty as its controlling
    terminal so it installs its SIGWINCH handler. stderr goes to a file for diagnosis."""

    def __init__(self, env=None, cwd=None, rows=24, cols=80):
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        attrs = termios.tcgetattr(slave)
        attrs[1] &= ~termios.OPOST
        attrs[3] &= ~(termios.ECHO | termios.ISIG)
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        self.workdir = scratch_dir("framer-proc-")
        self.stderr_path = os.path.join(self.workdir, "stderr.txt")
        full_env = dict(os.environ)
        full_env.update(env or {})
        with open(self.stderr_path, "wb") as err:
            self.proc = subprocess.Popen(
                _python_command(framer_copy()),
                stdin=slave, stdout=slave, stderr=err,
                cwd=cwd or self.workdir, env=full_env,
                start_new_session=True,
                preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
        os.close(slave)
        self.parser = FrameParser()
        self.raw = bytearray()
        self.cond = threading.Condition()
        self.eof = False
        self.consumed_replies = 0
        self.thread = threading.Thread(target=self._read_loop, daemon=True)
        self.thread.start()

    def _read_loop(self):
        while True:
            try:
                data = os.read(self.master, 65536)
            except OSError:
                data = b""
            with self.cond:
                if not data:
                    self.eof = True
                    self.cond.notify_all()
                    return
                self.raw += data
                self.parser.feed(data)
                self.cond.notify_all()

    def write(self, data):
        view = memoryview(data)
        while view:
            n = os.write(self.master, view)
            view = view[n:]

    def send(self, *args, chunk_size=128):
        self.write(encode_command(args, chunk_size))

    def wait(self, predicate, timeout=TIMEOUT):
        with self.cond:
            return self.cond.wait_for(predicate, timeout)

    def next_reply(self, timeout=TIMEOUT):
        """The next reply in the order commands were sent, as iTerm2 matches them."""
        def ready():
            return (len(self.parser.replies()) > self.consumed_replies or self.parser.unhooked
                    or self.eof)
        self.wait(ready, timeout)
        with self.cond:
            replies = self.parser.replies()
            if len(replies) <= self.consumed_replies:
                return None
            self.consumed_replies += 1
            return replies[self.consumed_replies - 1]

    def command(self, *args, **kwargs):
        self.send(*args, **kwargs)
        return self.next_reply()

    def reattach(self):
        """A new iTerm2 takes over the connection: forget what was parsed and start a parser
        in recovery mode, as Conductor does when it restores a session."""
        with self.cond:
            self.parser = FrameParser(recovery_mode=True)
            self.consumed_replies = 0

    def exited(self, timeout=TIMEOUT):
        """Waits for the framer to exit; returns its status or None."""
        try:
            return self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            return None

    def send_eof(self):
        # VEOF at the start of a line: readline() returns "" in canonical mode.
        self.write(b"\x04")

    def stderr(self):
        with open(self.stderr_path, "rb") as f:
            return f.read().decode("utf-8", "replace")

    def diagnostics(self):
        return "errors=%r\nstderr=%s\nraw tail=%r" % (
            self.parser.errors, self.stderr(), bytes(self.raw[-600:]))

    def close(self, extra_pids=()):
        for pid in extra_pids:
            with contextlib.suppress(OSError):
                os.killpg(pid, signal.SIGKILL)
            with contextlib.suppress(OSError):
                os.kill(pid, signal.SIGKILL)
        if self.proc.poll() is None:
            with contextlib.suppress(OSError):
                os.killpg(self.proc.pid, signal.SIGKILL)
            self.proc.wait(TIMEOUT)
        self.thread.join(TIMEOUT)
        with contextlib.suppress(OSError):
            os.close(self.master)
        shutil.rmtree(self.workdir, ignore_errors=True)


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_until(predicate, timeout=TIMEOUT, interval=0.01):
    """For conditions nothing signals (another process's state). Polls with a deadline."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()
