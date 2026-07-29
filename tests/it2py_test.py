#!/usr/bin/env python3
"""Round-trips OtherResources/it2.py against a fake framer socket to exercise the
wire protocol: HELLO upstream (argv/nonce/ctx), STDOUT/STDERR/EXIT downstream, and
the failure path where the connection drops before an EXIT frame.

Run: python3 tests/it2py_test.py
"""
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
IT2 = os.path.join(HERE, "..", "OtherResources", "it2.py")

# Also import it2.py as a module (no side effects; main() is __main__-guarded) for unit tests.
import importlib.util
_spec = importlib.util.spec_from_file_location("it2_under_test", IT2)
it2mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(it2mod)


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        c = conn.recv(n - len(buf))
        if not c:
            return None
        buf += c
    return buf


def recv_frame(conn):
    h = recv_exact(conn, 5)
    if h is None:
        return None, None
    length = struct.unpack(">I", h[1:5])[0]
    return chr(h[0]), (recv_exact(conn, length) if length else b"")


def send_frame(conn, ftype, payload=b""):
    if isinstance(payload, str):
        payload = payload.encode()
    conn.sendall(ftype.encode() + struct.pack(">I", len(payload)) + payload)


def run_scenario(serve_fn, argv):
    """Serve one connection via serve_fn(conn, captured) and run it2.py against it."""
    d = tempfile.mkdtemp()
    sock_path = os.path.join(d, "it2.sock")
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    srv.listen(1)
    srv.settimeout(10)  # accept() can't block forever if it2.py fails to connect
    captured = {}

    def serve():
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            return
        try:
            serve_fn(conn, captured)
        finally:
            conn.close()

    t = threading.Thread(target=serve, daemon=True)  # daemon: never wedges the interpreter
    t.start()
    env = dict(os.environ, IT2_SOCK=sock_path, IT2_NONCE="secret", TERM="xterm")
    try:
        result = subprocess.run([sys.executable, IT2] + argv, env=env,
                                capture_output=True, text=True, timeout=10)
    finally:
        t.join(timeout=5)
        srv.close()
        shutil.rmtree(d, ignore_errors=True)
    return result, captured


_ok = True


def check(cond, msg):
    global _ok
    if not cond:
        _ok = False
        print("FAIL:", msg)


def test_happy_path():
    def serve(conn, captured):
        ftype, payload = recv_frame(conn)
        captured["hello_type"] = ftype
        captured["hello"] = json.loads(payload.decode())
        send_frame(conn, "O", "hello world\n")
        send_frame(conn, "E", "a warning\n")
        send_frame(conn, "X", json.dumps({"code": 7}))

    result, captured = run_scenario(serve, ["session", "list"])
    check(captured.get("hello_type") == "H", "expected HELLO frame, got %r" % captured.get("hello_type"))
    check(captured.get("hello", {}).get("argv") == ["session", "list"], "argv forwarded: %r" % captured.get("hello"))
    check(captured.get("hello", {}).get("nonce") == "secret", "nonce forwarded")
    check(result.stdout == "hello world\n", "stdout mismatch: %r" % result.stdout)
    check(result.stderr == "a warning\n", "stderr mismatch: %r" % result.stderr)
    check(result.returncode == 7, "exit code mismatch: %r" % result.returncode)


def test_disconnect_without_exit():
    def serve(conn, _captured):
        recv_frame(conn)  # HELLO
        send_frame(conn, "O", "partial output\n")
        # Close without an EXIT frame (server crash / killed job / reset).

    result, _ = run_scenario(serve, ["session", "list"])
    check(result.stdout == "partial output\n", "partial stdout still delivered: %r" % result.stdout)
    check(result.returncode != 0, "premature close must be nonzero, got %r" % result.returncode)
    check("closed before completion" in result.stderr, "expected note on stderr: %r" % result.stderr)


def test_broken_stdout_pipe_no_shutdown_traceback():
    """`it2 monitor -f | head -1`: the reader takes one line and exits, breaking it2.py's
    stdout mid-stream. it2.py must exit 141 cleanly WITHOUT Python printing a spurious
    "Exception ignored in ... BrokenPipeError" traceback when it flushes stdout during
    interpreter shutdown."""
    d = tempfile.mkdtemp()
    sock_path = os.path.join(d, "it2.sock")
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    srv.listen(1)
    srv.settimeout(10)

    def serve():
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            return
        try:
            recv_frame(conn)  # HELLO
            # Flood STDOUT so it2.py keeps writing until the pipe (reader closed) breaks.
            try:
                for i in range(200000):
                    send_frame(conn, "O", "line %d\n" % i)
            except OSError:
                pass  # it2.py closed the socket after the broken pipe; stop flooding
        finally:
            conn.close()

    t = threading.Thread(target=serve, daemon=True)
    t.start()
    env = dict(os.environ, IT2_SOCK=sock_path, IT2_NONCE="secret", TERM="xterm")
    # A one-line reader standing in for `head -1`: it reads a single line then exits,
    # closing the read end so it2.py's next stdout write gets a broken pipe.
    reader = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.readline()"],
                              stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    try:
        result = subprocess.run([sys.executable, IT2, "monitor", "output", "-f"], env=env,
                                stdout=reader.stdin, stderr=subprocess.PIPE, text=True, timeout=10)
    finally:
        try:
            reader.stdin.close()
        except OSError:
            pass
        reader.wait(timeout=5)
        t.join(timeout=5)
        srv.close()
        shutil.rmtree(d, ignore_errors=True)
    check("BrokenPipeError" not in result.stderr,
          "no BrokenPipeError traceback on stderr: %r" % result.stderr)
    check("Exception ignored" not in result.stderr,
          "no 'Exception ignored' shutdown traceback: %r" % result.stderr)
    check(result.returncode == 141, "broken pipe mirrors SIGPIPE (141): %r" % result.returncode)


def test_write_raw_broken_pipe_before_first_write():
    """A broken pipe on the FIRST write (consumer exited before any byte, e.g. `it2 cmd |
    head -c0`) must be reported as broke (False), not tolerated as 'never usable' -- otherwise
    output is silently dropped, no CANCEL is sent, and the exit code is wrong. A non-pipe
    failure (EBADF from `>&-`) on a never-written stream stays tolerated (True)."""
    class _Buf:
        def __init__(self, exc):
            self._exc = exc
        def write(self, _):
            raise self._exc
        def flush(self):
            pass
    class _Stream:
        def __init__(self, exc):
            self.buffer = _Buf(exc)

    it2mod._usable_streams.clear()
    check(it2mod.write_raw(_Stream(BrokenPipeError()), b"x") is False,
          "broken pipe on the first write must be reported as broke")
    it2mod._usable_streams.clear()
    check(it2mod.write_raw(_Stream(ConnectionResetError()), b"x") is False,
          "connection reset on the first write must be reported as broke")
    it2mod._usable_streams.clear()
    check(it2mod.write_raw(_Stream(OSError(9, "Bad file descriptor")), b"x") is True,
          "EBADF (>&-) on a never-written stream stays tolerated")


def test_recv_exact_total_deadline_bounds_slow_trickle():
    """recv_exact must bound the WHOLE read by the deadline. A slow trickle (each byte arrives
    within the per-recv window but the payload never completes) must still time out -- a per-recv
    idle timeout would be reset by every byte and never fire. Huge margin (0.3s deadline vs the
    ~200s it would take to read the byte count at this trickle rate) keeps it non-flaky."""
    a, b = socket.socketpair()
    stop = threading.Event()

    def trickle():
        while not stop.is_set():
            try:
                b.send(b"x")
            except OSError:
                return
            time.sleep(0.02)

    t = threading.Thread(target=trickle, daemon=True)
    t.start()
    try:
        start = time.monotonic()
        raised = False
        try:
            it2mod.recv_exact(a, 10000, deadline=time.monotonic() + 0.3)
        except (socket.timeout, OSError):
            raised = True
        elapsed = time.monotonic() - start
        check(raised, "recv_exact must time out on a trickle bounded by the total deadline")
        check(elapsed < 3.0, "timed out near the deadline, not after reading everything (%.2fs)" % elapsed)
    finally:
        stop.set()
        a.close()
        b.close()
        t.join(timeout=2)


def main():
    test_happy_path()
    test_disconnect_without_exit()
    test_broken_stdout_pipe_no_shutdown_traceback()
    test_write_raw_broken_pipe_before_first_write()
    test_recv_exact_total_deadline_bounds_slow_trickle()
    print("PASS" if _ok else "FAILED")
    return 0 if _ok else 1


if __name__ == "__main__":
    sys.exit(main())
