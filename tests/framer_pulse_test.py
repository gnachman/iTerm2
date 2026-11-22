#!/usr/bin/env python3
"""Exercises framer.py's PulseAudio socket-proxy handlers: pulselisten opens an
owner-only unix socket, exports PULSE_SERVER=unix:<path> into login/pane/shell
environments, relays concurrent streams as %pulse <connid> open|data|close,
delivers downstream frames via pulsesend, aborts on pulseclose and recover,
reclaims unlocked sockets via flock, sweeps stale /tmp/.it2-pulse-* directories,
and respects FLOW_PULSE credit in flow control v2.

Run: python3 tests/framer_pulse_test.py
"""
import asyncio
import base64
import contextlib
import fcntl
import importlib.util
import io
import os
import shutil
import signal as signal_module
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

_spec = importlib.util.spec_from_file_location("framer_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

_frames = []
framer.unlock = lambda writes: _frames.extend(
    w if isinstance(w, str) else w.decode("latin-1") for w in writes
)


def _unwrap(frame):
    if frame.startswith("\033]134;:") and frame.endswith("\033\\"):
        return frame[len("\033]134;:"):-2]
    return None


def pulse_frames():
    out = []
    for f in _frames:
        payload = _unwrap(f)
        if payload is not None and payload.startswith("%pulse "):
            out.append(payload)
    return out


def frames_of_kind(kind):
    return [f for f in pulse_frames() if f.split()[2] == kind]


def end_status(identifier):
    for f in _frames:
        payload = _unwrap(f)
        if payload is None:
            continue
        parts = payload.split()
        if len(parts) >= 3 and parts[0] == "end" and parts[1] == identifier:
            return int(parts[2])
    return None


def _reset_server():
    framer.FLOW.disable()
    framer.PULSE_GATE = None
    if framer.PULSE_SERVER_OBJ is not None:
        with contextlib.suppress(Exception):
            framer.PULSE_SERVER_OBJ.close()
        framer.PULSE_SERVER_OBJ = None
    framer.PULSE_SOCKET_PATH = None
    if framer.PULSE_LOCK_FD is not None:
        with contextlib.suppress(OSError):
            os.close(framer.PULSE_LOCK_FD)
        framer.PULSE_LOCK_FD = None
    framer.PULSE_LOCK_PATH = None
    framer.PULSE_SOCKET_TMPDIR = None
    for _writer in list(framer.PULSE_CONNS.values()):
        with contextlib.suppress(Exception):
            _writer.transport.abort()
    framer.PULSE_CONNS = {}
    framer.PULSE_LOCALLY_CLOSED.clear()


async def wait_for(predicate, timeout=2.0):
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return predicate()


def _make_socket_file(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.close()


async def test_happy_path_and_env_export():
    print("test_happy_path_and_env_export")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    saved_pulse_env = os.environ.pop("PULSE_SERVER", None)
    d = tempfile.mkdtemp()
    path = os.path.join(d, "native")
    try:
        await framer.handle_pulselisten("id-pl", [path])
        check(end_status("id-pl") == 0, "pulselisten succeeded")
        check(framer.PULSE_SERVER_OBJ is not None, "pulse server started")
        check(os.path.exists(path), "socket file created")

        env = framer.login_shell_environment()
        check(env.get("PULSE_SERVER") == "unix:" + path,
              "login_shell_environment sets PULSE_SERVER: %r" % env.get("PULSE_SERVER"))

        # Explicit user PULSE_SERVER override is respected.
        os.environ["PULSE_SERVER"] = "unix:/custom/pulse"
        env_custom = framer.login_shell_environment()
        check(env_custom.get("PULSE_SERVER") == "unix:/custom/pulse",
              "custom PULSE_SERVER preserved")
        os.environ.pop("PULSE_SERVER", None)

        reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        opens = frames_of_kind("open")
        check(len(opens) == 1, "one open frame: %r" % pulse_frames())
        connid = opens[0].split()[1]

        writer.write(b"\x00\x00\x00\x14\xff\xff\xff\xffAUTH")
        await writer.drain()
        await wait_for(lambda: frames_of_kind("data"))
        datas = frames_of_kind("data")
        check(len(datas) >= 1, "data frame emitted")
        if datas:
            check(base64.b64decode(datas[0].split()[3]) == b"\x00\x00\x00\x14\xff\xff\xff\xffAUTH",
                  "pstream payload round-trips")

        await framer.handle_pulsesend("id-ps", [connid, base64.b64encode(b"REPLY-35").decode()])
        check(end_status("id-ps") == 0, "pulsesend succeeded")
        got = await asyncio.wait_for(reader.read(8), timeout=2)
        check(got == b"REPLY-35", "client received reply: %r" % got)

        await framer.handle_pulseclose("id-pc", [connid])
        await wait_for(lambda: connid not in framer.PULSE_LOCALLY_CLOSED)
        check(len(frames_of_kind("close")) == 0, "no duplicate close on pulseclose")
        eof = await asyncio.wait_for(reader.read(1), timeout=2)
        check(eof == b"", "client received EOF after pulseclose")
        writer.close()
    finally:
        if saved_pulse_env is not None:
            os.environ["PULSE_SERVER"] = saved_pulse_env
        else:
            os.environ.pop("PULSE_SERVER", None)
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_concurrent_playback_and_capture_multiplexing():
    print("test_concurrent_playback_and_capture_multiplexing")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    d = tempfile.mkdtemp()
    path = os.path.join(d, "native.sock")
    try:
        await framer.handle_pulselisten("id-mux", [path])
        r1, w1 = await asyncio.open_unix_connection(path)
        r2, w2 = await asyncio.open_unix_connection(path)
        await wait_for(lambda: len(frames_of_kind("open")) == 2)
        c1 = frames_of_kind("open")[0].split()[1]
        c2 = frames_of_kind("open")[1].split()[1]
        check(c1 != c2, "distinct connids assigned")

        pcm_up = bytes((i * 13) & 0xff for i in range(10000))  # > PULSE_READ_CHUNK (4096)
        w1.write(pcm_up)
        w2.write(b"RECORD-REQ")
        await w1.drain()
        await w2.drain()

        def c1_bytes():
            return b"".join(
                base64.b64decode(f.split()[3])
                for f in frames_of_kind("data")
                if f.split()[1] == c1
            )

        def c2_bytes():
            return b"".join(
                base64.b64decode(f.split()[3])
                for f in frames_of_kind("data")
                if f.split()[1] == c2
            )

        await wait_for(lambda: len(c1_bytes()) == len(pcm_up) and c2_bytes() == b"RECORD-REQ")
        check(c1_bytes() == pcm_up, "playback stream reassembled cleanly across chunks")
        check(c2_bytes() == b"RECORD-REQ", "capture stream isolated from playback stream")
        for f in frames_of_kind("data"):
            if f.split()[1] == c1:
                check(len(base64.b64decode(f.split()[3])) <= framer.PULSE_READ_CHUNK,
                      "chunk within PULSE_READ_CHUNK")

        await framer.handle_pulsesend("id-s2", [c2, base64.b64encode(b"MIC-PCM-DATA").decode()])
        mic = await asyncio.wait_for(r2.read(12), timeout=2)
        check(mic == b"MIC-PCM-DATA", "capture PCM delivered to second connection")

        w1.close()
        await wait_for(lambda: any(f.split()[1] == c1 for f in frames_of_kind("close")))
        check(c2 in framer.PULSE_CONNS, "second stream stays open when first disconnects")
        w2.close()
    finally:
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_permissions_flock_and_tmp_sweep():
    print("test_permissions_flock_and_tmp_sweep")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    tmp_root = tempfile.mkdtemp()
    saved_root = framer.IT2_TMP_SOCKET_ROOT
    framer.IT2_TMP_SOCKET_ROOT = tmp_root
    held_fd = None
    old = time.time() - 3600
    try:
        dead_dir = os.path.join(tmp_root, ".it2-pulse-dead")
        os.mkdir(dead_dir, 0o700)
        _make_socket_file(os.path.join(dead_dir, "native"))
        open(os.path.join(dead_dir, "native.lock"), "w").close()
        os.utime(dead_dir, (old, old))

        live_dir = os.path.join(tmp_root, ".it2-pulse-live")
        os.mkdir(live_dir, 0o700)
        _make_socket_file(os.path.join(live_dir, "native"))
        held_fd = os.open(os.path.join(live_dir, "native.lock"), os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(held_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.utime(live_dir, (old, old))

        # Symlink attack in /tmp is rejected.
        target = tempfile.mkdtemp()
        planted = os.path.join(tmp_root, ".it2-pulse-planted")
        os.symlink(target, planted)
        await framer.handle_pulselisten("id-sym", [os.path.join(planted, "native")])
        check(end_status("id-sym") == 1, "symlinked /tmp pulse dir refused")
        shutil.rmtree(target, ignore_errors=True)

        mine = os.path.join(tmp_root, ".it2-pulse-mine")
        path = os.path.join(mine, "native")
        _frames.clear()
        await framer.handle_pulselisten("id-mine", [path])
        check(end_status("id-mine") == 0, "listen in valid /tmp dir succeeded")
        check(stat.S_IMODE(os.stat(mine).st_mode) == 0o700, "socket dir is 0700")
        check(stat.S_IMODE(os.stat(path).st_mode) == 0o600, "socket is 0600")
        check(not os.path.exists(dead_dir), "dead pulse tmpdir swept")
        check(os.path.exists(os.path.join(live_dir, "native")), "live pulse socket preserved")

        # Verify _it2_sweep_stale_tmp_socket_dirs ignores .it2-pulse-* directories.
        framer._it2_sweep_stale_tmp_socket_dirs(keep_dir=None)
        check(os.path.isdir(mine), "it2 sweeper ignores .it2-pulse-*")

        framer._pulse_teardown_socket()
        check(not os.path.exists(mine), "teardown removes pulse /tmp directory")
    finally:
        if held_fd is not None:
            os.close(held_fd)
        framer.IT2_TMP_SOCKET_ROOT = saved_root
        _reset_server()
        shutil.rmtree(tmp_root, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_hangup_removes_pulse_tmp_socket_dir():
    print("test_hangup_removes_pulse_tmp_socket_dir")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    tmp_root = tempfile.mkdtemp()
    try:
        for sig in (signal_module.SIGHUP, signal_module.SIGTERM):
            socket_dir = os.path.join(tmp_root, ".it2-pulse-%d" % sig)
            script = "\n".join([
                "import importlib.util, os, signal",
                "spec = importlib.util.spec_from_file_location('f', %r)" % FRAMER_PATH,
                "f = importlib.util.module_from_spec(spec)",
                "spec.loader.exec_module(f)",
                "os.mkdir(%r, 0o700)" % socket_dir,
                "f.PULSE_SOCKET_PATH = os.path.join(%r, 'native')" % socket_dir,
                "open(f.PULSE_SOCKET_PATH, 'w').close()",
                "f.PULSE_LOCK_PATH = f.PULSE_SOCKET_PATH + '.lock'",
                "open(f.PULSE_LOCK_PATH, 'w').close()",
                "f.PULSE_SOCKET_TMPDIR = %r" % socket_dir,
                "f.install_terminating_signal_handlers()",
                "os.kill(os.getpid(), %d)" % sig,
                "signal.pause()",
            ])
            proc = subprocess.run([sys.executable, "-c", script], timeout=30)
            check(proc.returncode == -sig, "died of signal %d" % sig)
            check(not os.path.exists(socket_dir), "signal %d removed pulse socket dir" % sig)
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_recover_aborts_pulse_connections_and_buffer_cap():
    print("test_recover_aborts_pulse_connections_and_buffer_cap")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    saved_cap = framer.PULSE_WRITE_BUFFER_MAX
    framer.PULSE_WRITE_BUFFER_MAX = 256 * 1024
    d = tempfile.mkdtemp()
    path = os.path.join(d, "native")
    w1 = None
    w2 = None
    try:
        await framer.handle_pulselisten("id-rec", [path])
        r1, w1 = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        c1 = frames_of_kind("open")[0].split()[1]

        # Test handle_recover aborts open pulse connections while keeping listener alive.
        await framer.handle_recover("id-recover", [])
        check(framer.PULSE_CONNS == {}, "recover cleared PULSE_CONNS")
        check(framer.PULSE_SERVER_OBJ is not None, "recover kept listener open")

        # Test buffer cap drops stalled consumer without blocking.
        _frames.clear()
        _r2, w2 = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        c2 = frames_of_kind("open")[0].split()[1]
        big = base64.b64encode(b"p" * (8 * 1024 * 1024)).decode()
        for _ in range(8):
            await asyncio.wait_for(framer.handle_pulsesend("id-cap", [c2, big]), timeout=10)
            if c2 not in framer.PULSE_CONNS:
                break
        check(c2 not in framer.PULSE_CONNS, "over-cap stalled consumer dropped")
        await wait_for(lambda: any(f.split()[1] == c2 for f in frames_of_kind("close")))
        check(any(f.split()[1] == c2 for f in frames_of_kind("close")),
              "aborted stalled consumer emitted %pulse close")
    finally:
        framer.PULSE_WRITE_BUFFER_MAX = saved_cap
        for w in (w1, w2):
            if w is not None:
                with contextlib.suppress(Exception):
                    w.close()
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_flow_pulse_credit_lane():
    print("test_flow_pulse_credit_lane")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    try:
        # Check command_reader parses `grant pulse 1200`.
        framer.FLOW.enable(2)
        queue = asyncio.Queue()
        encoded = "".join(base64.b64encode(a.encode()).decode() + "\n"
                          for a in ("grant", "pulse", "1200")) + "\n"
        stream = io.StringIO(encoded)
        loop = asyncio.get_event_loop()
        thread = threading.Thread(target=framer.command_reader, args=(stream, loop, queue), daemon=True)
        thread.start()
        while await queue.get() is not None:
            pass
        await asyncio.sleep(0)
        check(framer.FLOW.credit_of(framer.FLOW_PULSE) == 1200,
              "command_reader granted FLOW_PULSE: %d" % framer.FLOW.credit_of(framer.FLOW_PULSE))

        # Check handle_pulse_connection respects FLOW_PULSE credit in v2.
        _frames.clear()
        framer.FLOW.enable(2)
        framer.flow_changed()
        reader = asyncio.StreamReader()
        reader.feed_data(b"a" * 6000)
        reader.feed_eof()

        class DummyWriter:
            def close(self):
                pass

        task = asyncio.ensure_future(framer.handle_pulse_connection(reader, DummyWriter()))
        await asyncio.sleep(0.05)
        check(len(frames_of_kind("data")) == 0, "held while FLOW_PULSE has 0 credit")

        framer.flow_grant(2000, framer.FLOW_PULSE)
        await wait_for(lambda: sum(len(base64.b64decode(f.split()[3]))
                                   for f in frames_of_kind("data")) >= 2000)
        got_first = sum(len(base64.b64decode(f.split()[3])) for f in frames_of_kind("data"))
        check(got_first == 2000, "spent exact 2000 byte grant, got %d" % got_first)
        last_parts = frames_of_kind("data")[-1].split()
        check(len(last_parts) == 6 and (int(last_parts[5]) & framer.FLOW_FLAG_LIMITED) != 0,
              "frame carries LIMITED flag: %r" % last_parts)

        framer.flow_grant(4000, framer.FLOW_PULSE)
        await asyncio.wait_for(task, timeout=5)
        total = sum(len(base64.b64decode(f.split()[3])) for f in frames_of_kind("data"))
        check(total == 6000, "all 6000 bytes delivered after second grant")
    finally:
        _reset_server()
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_current_symlink_tracks_live_and_cleans_up():
    print("test_current_symlink_tracks_live_and_cleans_up")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    d = tempfile.mkdtemp()
    sock_a = os.path.join(d, "aaaa1111.sock")
    sock_b = os.path.join(d, "bbbb2222.sock")
    current = os.path.join(d, framer.PULSE_CURRENT_LINK_NAME)
    other_lock_fd = None
    try:
        # Simulate another live framer holding sock_a + sock_a.lock.
        _make_socket_file(sock_a)
        other_lock_fd = os.open(framer._it2_lock_path(sock_a), os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(other_lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)

        await framer.handle_pulselisten("id-cur", [sock_b])
        check(end_status("id-cur") == 0, "pulselisten succeeded")
        check(os.path.islink(current), "current symlink created")
        check(os.readlink(current) == os.path.basename(sock_b), "current points to newest bound socket")

        # Teardown of sock_b should fail over `current` to still-live sock_a.
        framer._pulse_teardown_socket()
        check(os.path.islink(current), "current fails over to still-live socket on teardown")
        check(os.readlink(current) == os.path.basename(sock_a), "current failed over to sock_a")

        # Once sock_a's lock is released, refresh/sweep removes dead `current`.
        fcntl.flock(other_lock_fd, fcntl.LOCK_UN)
        os.close(other_lock_fd)
        other_lock_fd = None
        framer._pulse_sweep_stale_sockets(d, keep=None)
        check(not os.path.lexists(current), "current unlinked when no live sockets remain")
    finally:
        if other_lock_fd is not None:
            with contextlib.suppress(OSError):
                fcntl.flock(other_lock_fd, fcntl.LOCK_UN)
                os.close(other_lock_fd)
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def run():
    results = []
    for test in (
        test_happy_path_and_env_export,
        test_concurrent_playback_and_capture_multiplexing,
        test_permissions_flock_and_tmp_sweep,
        test_hangup_removes_pulse_tmp_socket_dir,
        test_recover_aborts_pulse_connections_and_buffer_cap,
        test_flow_pulse_credit_lane,
        test_current_symlink_tracks_live_and_cleans_up,
    ):
        results.append(await test())
    ok = all(results)
    print("PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
