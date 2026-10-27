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
    # A real tmux server around the test run must not be consulted for its advertised socket.
    env.pop("TMUX", None)
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
    check(captured.get("hello", {}).get("protocol") == it2mod.PROTOCOL_VERSION,
          "protocol version sent: %r" % captured.get("hello"))
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
    # A real tmux server around the test run must not be consulted for its advertised socket.
    env.pop("TMUX", None)
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


class _FakeStdin:
    """Stands in for sys.stdin: .buffer.read() and .isatty(), with None meaning unreadable."""
    def __init__(self, data, isatty):
        self._data = data
        self._isatty = isatty
        self.buffer = self

    def isatty(self):
        return self._isatty

    def read(self, n=-1):
        if self._data is None:
            raise OSError("closed")
        if n is None or n < 0:
            return self._data
        return self._data[:n]


def _hex(s):
    return s.encode("utf-8").hex()


def _client_line(name, control="1", created=100, session=None):
    line = "IT2CLIENT\t%s\t%s\t%s" % (name, control, created)
    if session is not None:
        line += "\t%s" % session
    return line


def _pane_session_line(session):
    return "IT2PANESESSION\t%s" % session


def _option_line(name, record_json):
    return "@it2_client_%s c_%s" % (_hex(name), _hex(record_json))


def test_parse_tmux_client_records():
    # The wire form TmuxController's advertiseIT2Client writes: one global user option per
    # attached client, keyed by the hex of its tmux client name, holding c_ + hex(JSON).
    output = "\n".join([
        _client_line("/dev/pts/3", created=100),
        _client_line("/dev/pts/4", created=200),
        _client_line("/dev/pts/7", control="0", created=300),   # plain client: never counts
        _client_line("short"),                                   # too few fields
        _option_line("/dev/pts/3", '{"nonce":"older","sock":"/a.sock"}'),
        _option_line("/dev/pts/4", '{"nonce":"newer","sock":"/b.sock"}'),
        _option_line("/dev/pts/7", '{"nonce":"plain","sock":"/c.sock"}'),
        _option_line("/dev/pts/9", '{"nonce":"stale","sock":"/d.sock"}'),  # not attached
        "@it2_client_zz c_00",                                   # bad hex name
        "@it2_client_%s x_%s" % (_hex("/dev/pts/4"), _hex("{}")),   # wrong tag
        "@it2_client_%s c_abc" % _hex("/dev/pts/3"),             # odd-length hex
        "@it2_client_%s c_%s" % (_hex("/dev/pts/3"), _hex("[1]")),  # not an object
        "@it2_client_novalue",
        "status on",
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check(records == [{"nonce": "newer", "sock": "/b.sock"},
                      {"nonce": "older", "sock": "/a.sock"}],
          "attached control clients only, newest first, garbage skipped: got %r" % records)
    # show-options may quote a value; ours never needs it, but tolerate it.
    quoted = "\n".join([_client_line("/dev/pts/3"),
                        '@it2_client_%s "c_%s"' % (_hex("/dev/pts/3"), _hex('{"suite":"x"}'))])
    check(it2mod.parse_tmux_client_records(quoted) == [{"suite": "x"}], "quoted value accepted")
    # Very old tmux prints nothing for an unknown format variable; only an explicit 0 rejects.
    empty_control = "\n".join([_client_line("/dev/pts/3", control=""),
                               _option_line("/dev/pts/3", '{"suite":"x"}')])
    check(it2mod.parse_tmux_client_records(empty_control) == [{"suite": "x"}],
          "empty client_control_mode accepted")
    check(it2mod.parse_tmux_client_records("") == [], "empty output")


def test_tmux_query_uses_one_invocation_with_real_tabs():
    args = it2mod.tmux_query_arguments("/tmp/od,d,socket", "")
    check(args[:3] == ["tmux", "-S", "/tmp/od,d,socket"], "socket passed through verbatim")
    check(";" in args, "both commands run in one tmux client")
    fmt = args[args.index("-F") + 1]
    check(fmt == "IT2CLIENT\t#{client_name}\t#{client_control_mode}\t#{client_created}\t#{session_id}",
          "format: %r" % fmt)
    check("\\t" not in fmt, "tmux does not interpret backslash escapes in formats")
    check("display-message" not in args, "no pane, nothing to ask about it")


def test_tmux_query_asks_which_session_holds_the_pane():
    args = it2mod.tmux_query_arguments("/tmp/s", "%7")
    check("display-message" in args, "the pane's session is asked for in the same invocation")
    i = args.index("display-message")
    check(args[i:i + 4] == ["display-message", "-p", "-t", "%7"], "targets the pane: %r" % args[i:i + 4])
    check(args[i + 4] == "IT2PANESESSION\t#{session_id}", "format: %r" % args[i + 4])


def test_client_and_pane_sessions_use_the_same_format():
    # F-911: #{client_session} is a session NAME ("A") and never equals the pane's
    # #{session_id} ("$0"), so the preference for the pane's own client silently did nothing.
    args = it2mod.tmux_query_arguments("/tmp/s", "%7")
    client_fields = args[args.index("-F") + 1].split("\t")
    pane_fields = args[args.index("display-message") + 4].split("\t")
    check(client_fields[4] == pane_fields[1],
          "client and pane session fields differ: %r vs %r" % (client_fields[4], pane_fields[1]))
    check(pane_fields[1] == "#{session_id}", "ids survive a rename; names do not")


def test_client_showing_the_pane_is_preferred_over_the_newest():
    # The 2026-09-28 failure. Two iTerm2 connections attached to one server, each driving a
    # different tmux session. The pane lives in $9, held by the OLDER client; the newer one
    # cannot place it. Newest-first alone sent every call to the wrong connection, which
    # answered "No session is showing that tmux pane".
    output = "\n".join([
        _client_line("/dev/pts/3", created=100, session="$9"),
        _client_line("/dev/pts/4", created=200, session="$10"),
        _option_line("/dev/pts/3", '{"nonce":"holds-the-pane","sock":"/a.sock"}'),
        _option_line("/dev/pts/4", '{"nonce":"newest","sock":"/b.sock"}'),
        _pane_session_line("$9"),
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check(records[0] == {"nonce": "holds-the-pane", "sock": "/a.sock"},
          "the client attached to the pane's session goes first: %r" % records)
    # The other is kept as a fallback rather than dropped: it may still be reachable when the
    # preferred one's socket is gone.
    check(len(records) == 2 and records[1]["nonce"] == "newest", "others still offered: %r" % records)


def test_newest_first_still_breaks_ties_within_the_preferred_group():
    # A window can be linked into two sessions, so two clients can both hold the pane.
    output = "\n".join([
        _client_line("/dev/pts/3", created=100, session="$9"),
        _client_line("/dev/pts/4", created=200, session="$9"),
        _option_line("/dev/pts/3", '{"nonce":"older"}'),
        _option_line("/dev/pts/4", '{"nonce":"newer"}'),
        _pane_session_line("$9"),
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check([r["nonce"] for r in records] == ["newer", "older"],
          "newest first among clients that can all place it: %r" % records)


def test_falls_back_to_newest_when_the_pane_session_is_unknown():
    # Old tmux, a stale TMUX_PANE, or a display-message that failed: no IT2PANESESSION line.
    # The previous rule is the fallback, not an error.
    output = "\n".join([
        _client_line("/dev/pts/3", created=100, session="$9"),
        _client_line("/dev/pts/4", created=200, session="$10"),
        _option_line("/dev/pts/3", '{"nonce":"older"}'),
        _option_line("/dev/pts/4", '{"nonce":"newer"}'),
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check([r["nonce"] for r in records] == ["newer", "older"],
          "unknown pane session falls back to newest first: %r" % records)


def test_only_the_hook_command_reads_stdin():
    # Reading stdin for every command hangs the ones that do not expect it: stdin is often an
    # inherited pipe that never reaches EOF. This was not hypothetical -- making it
    # unconditional made `it2 session list` time out in this very file.
    check(it2mod.wants_stdin(["handle-agent-hook"]), "the hook reads its payload")
    check(it2mod.wants_stdin(["handle-agent-hook", "--agent", "codex"]), "with arguments")
    check(not it2mod.wants_stdin(["session", "list"]), "session list must not drain stdin")
    check(not it2mod.wants_stdin([]), "no command, nothing to read")
    check(not it2mod.wants_stdin(["--version"]), "a bare flag is not a stdin command")


def test_stdin_is_read_when_not_a_tty():
    # A hook's payload arrives on stdin. Without this a remote `it2 handle-agent-hook` has
    # nothing to act on, which is the whole reason 3b exists.
    payload = b'{"hook_event_name":"PreToolUse"}'
    data = it2mod.read_stdin_payload(_FakeStdin(payload, isatty=False))
    check(data == payload, "got %r" % data)


def test_stdin_is_not_read_from_a_tty():
    # An interactive `it2 session list` must not block waiting for the user to type EOF.
    check(it2mod.read_stdin_payload(_FakeStdin(b"ignored", isatty=True)) is None,
          "a tty must not be drained")


def test_stdin_is_capped():
    big = b"x" * (it2mod.MAX_STDIN_BYTES + 5000)
    data = it2mod.read_stdin_payload(_FakeStdin(big, isatty=False))
    check(len(data) == it2mod.MAX_STDIN_BYTES, "capped to %d, got %d" % (it2mod.MAX_STDIN_BYTES, len(data)))


def test_stdin_unreadable_is_not_fatal():
    # A closed or broken stdin must degrade to "no payload", not kill the command.
    check(it2mod.read_stdin_payload(_FakeStdin(None, isatty=False)) is None,
          "an unreadable stdin yields no payload")


def test_env_allowlist_sends_only_what_is_listed():
    env = {"TMUX": "/tmp/s,1,0", "TMUX_PANE": "%3", "TERM_SESSION_ID": "w0t0p0:ABC",
           "IT2_SUITE": "alt7", "IT2_PY": "/home/u/.iterm2/it2.abc.py",
           "AWS_SECRET_ACCESS_KEY": "nope", "PATH": "/usr/bin"}
    sent = it2mod.allowed_environment(env)
    check(sorted(sent) == ["IT2_PY", "IT2_SUITE", "TERM_SESSION_ID", "TMUX", "TMUX_PANE"],
          "allowlist leaked or dropped: %r" % sorted(sent))
    check("AWS_SECRET_ACCESS_KEY" not in sent, "secrets must never cross the wire")
    check(sent["TMUX_PANE"] == "%3", "values pass through")


def test_env_allowlist_omits_absent_variables():
    sent = it2mod.allowed_environment({"TMUX": "/tmp/s,1,0"})
    check(sent == {"TMUX": "/tmp/s,1,0"}, "absent names must not appear as empty: %r" % sent)


def test_tmux_is_found_through_its_server():
    # tmux started by its full path leaves none on PATH; the server's own executable is used.
    check(it2mod.tmux_executable(str(os.getpid()), which=lambda name: "/opt/tmux") == "/opt/tmux",
          "tmux on PATH wins")
    # A stand-in server started by its full path, as the tmux in question is.
    server = subprocess.Popen([os.path.realpath(sys.executable), "-c", "import time; time.sleep(30)"])
    try:
        found = it2mod.tmux_executable(str(server.pid), which=lambda name: None)
        check(found is not None and os.path.isabs(found) and os.access(found, os.X_OK),
              "the server's own executable: %r" % found)
    finally:
        server.kill()
        server.wait()
    check(it2mod.tmux_executable("not-a-pid", which=lambda name: None) is None, "bad pid")
    check(it2mod.tmux_executable("999999999", which=lambda name: None) is None, "no such process")


def test_tmux_query_runs_the_tmux_it_found():
    args = it2mod.tmux_query_arguments("/tmp/s", "", "/opt/homebrew/bin/tmux")
    check(args[0] == "/opt/homebrew/bin/tmux", "argv0: %r" % args[0])


def test_unreadable_tmux_server_fails_instead_of_using_the_inherited_socket():
    # Inside tmux with no tmux to ask, the inherited IT2_SOCK belongs to whichever connection
    # started the server, and a command sent there would act on that connection's session.
    d = tempfile.mkdtemp()
    try:
        env = dict(os.environ, IT2_SOCK=os.path.join(d, "never-used.sock"), IT2_NONCE="x",
                   TMUX="/tmp/no-such-tmux-socket,999999999,0", TMUX_PANE="%1",
                   PATH=d)
        result = subprocess.run([sys.executable, IT2, "app", "version"], env=env,
                                capture_output=True, text=True, timeout=10)
        check(result.returncode == 2, "exit status: %r" % result.returncode)
        check("tmux" in result.stderr and "cannot reach" not in result.stderr,
              "says why: %r" % result.stderr)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_tmux_that_reaches_no_server_fails_too():
    # A tmux that runs but reaches no server (another protocol version, a socket this user can't
    # open) exits nonzero with no output. That is not "no iTerm2 attached".
    d = tempfile.mkdtemp()
    try:
        fake = os.path.join(d, "tmux")
        with open(fake, "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        os.chmod(fake, 0o755)
        env = dict(os.environ, IT2_SOCK=os.path.join(d, "never-used.sock"), IT2_NONCE="x",
                   TMUX="/tmp/no-such-tmux-socket,999999999,0", TMUX_PANE="%1",
                   PATH=d + ":/usr/bin:/bin")
        result = subprocess.run([sys.executable, IT2, "app", "version"], env=env,
                                capture_output=True, text=True, timeout=10)
        check(result.returncode == 2, "exit status: %r" % result.returncode)
        check("did not say" in result.stderr, "says why: %r" % result.stderr)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_records_survive_a_partial_query():
    # A stale $TMUX_PANE makes display-message fail, so tmux exits nonzero after the earlier
    # commands have already printed. The records must survive that: the pane going away does
    # not mean no iTerm2 is attached.
    output = "\n".join([
        _client_line("/dev/pts/4", created=200, session="$10"),
        _option_line("/dev/pts/4", '{"nonce":"newer"}'),
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check([r["nonce"] for r in records] == ["newer"], "partial output still parses: %r" % records)


def test_no_client_holds_the_pane():
    # iTerm2 is attached, but to a session that does not contain this pane. Every record is a
    # fallback; none is preferred.
    output = "\n".join([
        _client_line("/dev/pts/4", created=200, session="$10"),
        _option_line("/dev/pts/4", '{"nonce":"newer"}'),
        _pane_session_line("$9"),
    ]) + "\n"
    records = it2mod.parse_tmux_client_records(output)
    check([r["nonce"] for r in records] == ["newer"], "still offered as a fallback: %r" % records)


def test_connect_to_iterm2_tries_candidates_in_order():
    # Two candidates whose sockets are dead, then one that is live: the live one is used, with
    # ITS nonce, never a socket from one record paired with the nonce of another.
    tmpdir = tempfile.mkdtemp()
    try:
        live_path = os.path.join(tmpdir, "live.sock")
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(live_path)
        server.listen(1)
        dead_path = os.path.join(tmpdir, "dead.sock")
        candidates = [{"sock": os.path.join(tmpdir, "missing.sock"), "nonce": "missing"},
                      {"sock": dead_path, "nonce": "dead"},
                      {"sock": 7, "nonce": "not-a-string"},
                      {"nonce": "no-sock"},
                      {"sock": live_path, "nonce": "live"},
                      {"sock": live_path, "nonce": "never-reached"}]
        sock, nonce = it2mod.connect_to_iterm2(candidates)
        check(sock is not None, "connected to the live candidate")
        check(nonce == "live", "nonce comes from the same record as the socket: %r" % nonce)
        if sock is not None:
            sock.close()
        sock, error = it2mod.connect_to_iterm2(candidates[:2])
        check(sock is None, "no live candidate: no socket")
        check(isinstance(error, str) and dead_path in error, "last failure reported: %r" % error)
        sock, error = it2mod.connect_to_iterm2([])
        check(sock is None and error is None, "no candidates at all")
        server.close()
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _write_file(path, contents, mode=0o644):
    with open(path, "w") as f:
        f.write(contents)
    os.chmod(path, mode)


def test_reexec_path():
    tmpdir = tempfile.mkdtemp()
    try:
        own = os.path.join(tmpdir, "it2.aaaa.py")
        other = os.path.join(tmpdir, "it2.bbbb.py")
        _write_file(own, "")
        _write_file(other, "")
        link = os.path.join(tmpdir, "link.py")
        os.symlink(own, link)
        check(it2mod.reexec_path({"py": other}, own, {}) == other, "a different copy is used")
        check(it2mod.reexec_path({"py": own}, own, {}) is None, "not this file")
        check(it2mod.reexec_path({"py": link}, own, {}) is None, "not this file by another name")
        check(it2mod.reexec_path({}, own, {}) is None, "no py: keep running")
        check(it2mod.reexec_path({"py": 7}, own, {}) is None, "not a string")
        check(it2mod.reexec_path({"py": "it2.bbbb.py"}, own, {}) is None, "relative paths are refused")
        check(it2mod.reexec_path({"py": os.path.join(tmpdir, "gone.py")}, own, {}) is None,
              "a copy that is not there (upload pending, cleaned up) is not run")
        check(it2mod.reexec_path({"py": other}, own, {it2mod.REEXEC_GUARD_NAME: "1"}) is None,
              "only once")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def test_record_py_is_reexeced_with_the_same_argv_and_stdin():
    # A pane whose tmux server froze an old IT2_PY: the attached controller's record names the
    # copy its connection uploaded, and that copy is the one that runs the command.
    tmpdir = tempfile.mkdtemp()
    try:
        sock_path = os.path.join(tmpdir, "live.sock")
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(sock_path)
        server.listen(4)
        marker = os.path.join(tmpdir, "marker.json")
        copy = os.path.join(tmpdir, "it2.cccc.py")
        _write_file(copy, "\n".join([
            "import json, os, sys",
            "json.dump({'argv': sys.argv[1:], 'stdin': sys.stdin.read(),",
            "           'py': os.environ.get('IT2_PY'),",
            "           'guard': os.environ.get('%s')}, open(%r, 'w'))" % (it2mod.REEXEC_GUARD_NAME, marker),
            "sys.exit(42)",
            ""]))
        record = json.dumps({"sock": sock_path, "nonce": "n", "py": copy})
        output = "\n".join([_client_line("/dev/pts/1"), _option_line("/dev/pts/1", record)])
        bindir = os.path.join(tmpdir, "bin")
        os.mkdir(bindir)
        _write_file(os.path.join(bindir, "tmux"), "#!/bin/sh\ncat <<'EOF'\n%s\nEOF\n" % output, 0o755)
        env = dict(os.environ, TMUX="%s,1,$0" % os.path.join(tmpdir, "tmux.sock"), TMUX_PANE="%0",
                   PATH=bindir + os.pathsep + os.environ.get("PATH", ""), IT2_PY="/stale/it2.py")
        env.pop("IT2_SOCK", None)
        env.pop(it2mod.REEXEC_GUARD_NAME, None)
        result = subprocess.run([sys.executable, IT2, "handle-agent-hook", "--x"], env=env,
                                input="payload", capture_output=True, text=True, timeout=10)
        server.close()
        check(result.returncode == 42, "the record's copy ran: %r %r" % (result.returncode, result.stderr))
        try:
            seen = json.load(open(marker))
        except (OSError, ValueError):
            seen = {}
        check(seen.get("argv") == ["handle-agent-hook", "--x"], "same argv: %r" % seen)
        check(seen.get("stdin") == "payload", "stdin untouched before the exec: %r" % seen)
        check(seen.get("py") == copy, "IT2_PY names the copy, not the stale value: %r" % seen)
        check(seen.get("guard") == "1", "guarded against a second exec: %r" % seen)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def main():
    # Every test_ function, so a new test cannot be written and then silently never run.
    tests = [value for name, value in sorted(globals().items())
             if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
    print("PASS" if _ok else "FAILED")
    return 0 if _ok else 1


if __name__ == "__main__":
    sys.exit(main())
