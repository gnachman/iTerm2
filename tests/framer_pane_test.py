#!/usr/bin/env python3
"""Exercises framer.py's pane processes: programs a workgroup peer runs through the leader's
framer instead of a new ssh connection. A pane gets its own pty as its controlling terminal
(so ^C reaches it), the framer's environment (not LANG=C), its own window size that the
framer's SIGWINCH handling leaves alone, and output on the pane channel, which iTerm2 never
draws into the leader. It is not the login shell: recovery reports it as a plain process and
its terminal modes are not reported as the leader's.

Run: python3 tests/framer_pane_test.py
"""
import asyncio
import base64
import fcntl
import importlib.util
import os
import pty
import signal
import struct
import sys
import tempfile
import termios

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

# A shell starts background jobs with SIGINT ignored, and children inherit that, so ^C
# would not interrupt the pane. Restore the default however this test was started.
signal.signal(signal.SIGINT, signal.default_int_handler)

_spec = importlib.util.spec_from_file_location("framer_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

# Capture frames instead of writing them to stdout.
_frames = []
framer.unlock = lambda writes: _frames.extend(
    w if isinstance(w, str) else w.decode("latin-1") for w in writes
)

OSC = "\033]134;:"
ST = "\033\\"


def payloads():
    """OSC 134 payloads in order, with the raw bytes between an %output header and its %end
    attached to the header as ("%output ...", data)."""
    result = []
    current = None
    for f in _frames:
        if f.startswith(OSC) and f.endswith(ST):
            p = f[len(OSC):-len(ST)]
            if current is not None and p == "%end " + current[0].split()[1]:
                result.append(tuple(current))
                current = None
            elif p.startswith("%output "):
                current = [p, ""]
            else:
                result.append((p, None))
        elif current is not None:
            current[1] += f
    return result


def pane_output(pid):
    return "".join(data for p, data in payloads()
                   if p.startswith("%output ") and p.split()[2] == str(pid))


def output_channels(pid):
    return {p.split()[3] for p, _ in payloads()
            if p.startswith("%output ") and p.split()[2] == str(pid)}


def terminated(pid):
    for p, _ in payloads():
        parts = p.split()
        if parts[0] == "%terminate" and parts[1] == str(pid):
            return int(parts[2])
    return None


def begun_pid(identifier):
    """The pid a pane command reported between begin and end for identifier, or None."""
    inside = False
    for p, _ in payloads():
        if p == "begin " + identifier:
            inside = True
        elif inside and p.startswith("end " + identifier + " "):
            return None
        elif inside:
            return int(p)
    return None


def end_status(identifier):
    for p, _ in payloads():
        parts = p.split()
        if len(parts) >= 3 and parts[0] == "end" and parts[1] == identifier:
            return int(parts[2])
    return None


async def wait_for(predicate, timeout=10.0):
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return predicate()


async def start_pane(identifier, command, rows=24, cols=80, cwd=None):
    await framer.handle_pane(identifier, [str(rows), str(cols), cwd or os.getcwd(), command])
    return begun_pid(identifier)


async def run_to_exit(pid):
    """Pump the framer's exit handling until pid's %terminate is out."""
    async def done():
        await framer.cleanup()
        while framer.TASKS:
            await framer.TASKS.pop(0)
        return terminated(pid) is not None
    deadline = asyncio.get_event_loop().time() + 10
    while asyncio.get_event_loop().time() < deadline:
        if await done():
            return terminated(pid)
        await asyncio.sleep(0.01)
    return None


class Checker:
    def __init__(self, name):
        print(name)
        self.ok = True

    def __call__(self, cond, msg):
        if not cond:
            self.ok = False
            print("  FAIL:", msg)

    def result(self):
        print("  PASS" if self.ok else "  FAILED")
        return self.ok


async def test_output_goes_out_on_the_pane_channel():
    check = Checker("test_output_goes_out_on_the_pane_channel")
    _frames.clear()
    pid = await start_pane("id-pane", "printf 'hello\\n'; exit 3")
    check(end_status("id-pane") == 0, "pane command succeeded: %r" % payloads())
    check(pid is not None, "pane reported its pid")
    if pid is None:
        return check.result()
    check(await run_to_exit(pid) == 3, "pane's exit status reported: %r" % payloads())
    check("hello" in pane_output(pid), "output delivered: %r" % pane_output(pid))
    check(output_channels(pid) == {str(framer.PANE_CHANNEL)},
          "only the pane channel: %r" % output_channels(pid))
    check(pid not in framer.PROCESSES, "forgotten after exit")
    return check.result()


async def test_pane_has_a_controlling_terminal_and_the_framers_environment():
    check = Checker("test_pane_has_a_controlling_terminal_and_the_framers_environment")
    _frames.clear()
    os.environ["FRAMER_PANE_TEST"] = "inherited"
    os.environ["LANG"] = "en_US.UTF-8"
    try:
        pid = await start_pane(
            "id-env",
            "if (exec 3</dev/tty) 2>/dev/null; then echo ctty=yes; else echo ctty=no; fi; "
            "echo lang=$LANG var=$FRAMER_PANE_TEST")
        if pid is None:
            check(False, "no pid: %r" % payloads())
            return check.result()
        await run_to_exit(pid)
        out = pane_output(pid)
        check("ctty=yes" in out, "has a controlling terminal: %r" % out)
        check("lang=en_US.UTF-8" in out, "keeps the framer's LANG: %r" % out)
        check("var=inherited" in out, "inherits the framer's environment: %r" % out)
    finally:
        del os.environ["FRAMER_PANE_TEST"]
    return check.result()


async def test_pane_starts_in_the_directory_given():
    check = Checker("test_pane_starts_in_the_directory_given")
    _frames.clear()
    d = os.path.realpath(tempfile.mkdtemp())
    pid = await start_pane("id-cwd", "pwd -P", cwd=d)
    if pid is None:
        check(False, "no pid: %r" % payloads())
        return check.result()
    await run_to_exit(pid)
    check(d in pane_output(pid), "ran in %s: %r" % (d, pane_output(pid)))
    os.rmdir(d)
    return check.result()


async def test_pane_has_its_own_size_and_can_be_resized():
    check = Checker("test_pane_has_its_own_size_and_can_be_resized")
    _frames.clear()
    pid = await start_pane("id-size", "stty size; read line; stty size", rows=31, cols=97)
    if pid is None:
        check(False, "no pid: %r" % payloads())
        return check.result()
    check(await wait_for(lambda: "31 97" in pane_output(pid)), "initial size: %r" % pane_output(pid))

    # SIGWINCH resizes the framer's own processes to the framer's size; a pane keeps its own.
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 50, 200, 0, 0))
    saved_stdin = sys.stdin
    sys.stdin = os.fdopen(slave, "r")
    try:
        await framer.update_pty_size()
    finally:
        sys.stdin.close()
        sys.stdin = saved_stdin
        os.close(master)
    await framer.handle_panesize("id-resize", [str(pid), "40", "120"])
    check(end_status("id-resize") == 0, "resize accepted")
    await framer.handle_send("id-send", [str(pid), base64.b64encode(b"\n").decode()])
    check(await run_to_exit(pid) == 0, "exited")
    check("40 120" in pane_output(pid), "resized: %r" % pane_output(pid))
    check("50 200" not in pane_output(pid), "not given the framer's size: %r" % pane_output(pid))

    await framer.handle_panesize("id-resize-gone", [str(pid), "40", "120"])
    check(end_status("id-resize-gone") == 1, "resizing a process that is gone fails")
    return check.result()


async def test_control_c_interrupts_the_pane():
    check = Checker("test_control_c_interrupts_the_pane")
    _frames.clear()
    # Perl prints "ready" itself so the ^C cannot reach the shell before an exec.
    pid = await start_pane("id-int", "exec perl -e '$|=1; print \"ready\\n\"; sleep 30'")
    if pid is None:
        check(False, "no pid: %r" % payloads())
        return check.result()
    check(await wait_for(lambda: "ready" in pane_output(pid)), "started")
    await framer.handle_send("id-ctrl-c", [str(pid), base64.b64encode(b"\x03").decode()])
    status = await run_to_exit(pid)
    check(status is not None and status != 0, "interrupted, status %r" % status)
    return check.result()


async def test_pane_is_not_the_login_shell():
    check = Checker("test_pane_is_not_the_login_shell")
    _frames.clear()
    pid = await start_pane("id-notlogin", "stty -echo -icanon; echo ready; read line")
    if pid is None:
        check(False, "no pid: %r" % payloads())
        return check.result()
    check(await wait_for(lambda: "ready" in pane_output(pid)), "started")
    tty_notifs = [p for p, _ in payloads() if p.startswith("%notif tty")]
    check(tty_notifs == [], "a pane's terminal modes are not reported as the leader's: %r" % tty_notifs)

    _frames.clear()
    await framer.handle_recover("id-recover", [])
    recovery = [p for p, _ in payloads() if p.startswith("recovery: ")]
    check("recovery: process %d" % pid in recovery, "recovered as a process: %r" % recovery)
    check("recovery: login %d" % pid not in recovery, "not recovered as the login shell")

    await framer.handle_send("id-send", [str(pid), base64.b64encode(b"\n").decode()])
    check(await run_to_exit(pid) == 0, "exited")
    return check.result()


async def test_bad_arguments_fail():
    check = Checker("test_bad_arguments_fail")
    _frames.clear()
    await framer.handle_pane("id-short", ["24", "80"])
    check(end_status("id-short") == 1, "too few arguments")
    await framer.handle_pane("id-nan", ["x", "80", "/", "true"])
    check(end_status("id-nan") == 1, "rows not a number")
    await framer.handle_panesize("id-size-nan", ["1", "x", "80"])
    check(end_status("id-size-nan") == 1, "resize rows not a number")
    check(framer.PROCESSES == {}, "nothing started: %r" % framer.PROCESSES)
    return check.result()


async def run():
    framer.RUNLOOP = asyncio.get_running_loop()
    results = []
    for test in (
        test_output_goes_out_on_the_pane_channel,
        test_pane_has_a_controlling_terminal_and_the_framers_environment,
        test_pane_starts_in_the_directory_given,
        test_pane_has_its_own_size_and_can_be_resized,
        test_control_c_interrupts_the_pane,
        test_pane_is_not_the_login_shell,
        test_bad_arguments_fail,
    ):
        results.append(await test())
    ok = all(results)
    print("PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
