#!/usr/bin/env python3
"""Exercises framer.py's it2 socket-proxy handlers in isolation: it2listen opens a
unix socket, an accepted connection's bytes surface as %it2 data frames, it2send
delivers bytes back to the client, and close is reported. Also covers the two
failure modes that must not degrade the shared command loop or leave a socket
exposed: a chmod failure during listen tears the server down (and re-listen
recovers), and a stalled client cannot block it2send indefinitely.

Run: python3 tests/framer_it2_test.py
"""
import asyncio
import base64
import contextlib
import fcntl
import importlib.util
import os
import shutil
import socket
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

_spec = importlib.util.spec_from_file_location("framer_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

# Capture frames instead of writing them to stdout.
_frames = []
framer.unlock = lambda writes: _frames.extend(
    w if isinstance(w, str) else w.decode("latin-1") for w in writes
)


def _unwrap(frame):
    """Return the OSC 134 payload of a captured frame, or None if not one."""
    if frame.startswith("\033]134;:") and frame.endswith("\033\\"):
        return frame[len("\033]134;:"):-2]
    return None


def it2_frames():
    out = []
    for f in _frames:
        payload = _unwrap(f)
        if payload is not None and payload.startswith("%it2 "):
            out.append(payload)
    return out


def frames_of_kind(kind):
    return [f for f in it2_frames() if f.split()[2] == kind]


def end_status(identifier):
    """Return the integer status a handler reported via end(...) for identifier."""
    for f in _frames:
        payload = _unwrap(f)
        if payload is None:
            continue
        parts = payload.split()
        if len(parts) >= 3 and parts[0] == "end" and parts[1] == identifier:
            return int(parts[2])
    return None


def _reset_server():
    if framer.IT2_SERVER is not None:
        with contextlib.suppress(Exception):
            framer.IT2_SERVER.close()
        framer.IT2_SERVER = None
    framer.IT2_SOCKET_PATH = None
    if framer.IT2_LOCK_FD is not None:
        with contextlib.suppress(OSError):
            os.close(framer.IT2_LOCK_FD)  # release the liveness lock a listen may hold
        framer.IT2_LOCK_FD = None
    framer.IT2_LOCK_PATH = None
    # Abort any accepted connections and clear the shared dict so a leaked writer + its
    # pending reader coroutine from one test cannot append a stray %it2 close frame during
    # the next (which would make frame-count assertions order-dependent / flaky).
    for _writer in list(framer.IT2_CONNS.values()):
        with contextlib.suppress(Exception):
            _writer.transport.abort()
    framer.IT2_CONNS = {}
    framer.IT2_LOCALLY_CLOSED.clear()


async def wait_for(predicate, timeout=2.0):
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return predicate()


async def test_happy_path():
    print("test_happy_path")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    await framer.handle_it2listen("id-listen", [path])
    check(framer.IT2_SERVER is not None, "server started")
    check(os.path.exists(path), "socket file created")

    reader, writer = await asyncio.open_unix_connection(path)

    await wait_for(lambda: frames_of_kind("open"))
    opens = frames_of_kind("open")
    check(len(opens) == 1, "exactly one open frame: %r" % it2_frames())
    connid = opens[0].split()[1]

    writer.write(b"HELLO-BYTES")
    await writer.drain()
    await wait_for(lambda: frames_of_kind("data"))
    datas = frames_of_kind("data")
    check(len(datas) >= 1, "data frame emitted: %r" % it2_frames())
    if datas:
        check(base64.b64decode(datas[0].split()[3]) == b"HELLO-BYTES", "data payload round-trips")

    await framer.handle_it2send("id-send", [connid, base64.b64encode(b"RESPONSE").decode()])
    got = await asyncio.wait_for(reader.read(8), timeout=2)
    check(got == b"RESPONSE", "client received response: %r" % got)

    await framer.handle_it2close("id-close", [connid])
    # iTerm2 initiated the close, so the framer must NOT echo a %it2 close back (a duplicate
    # for a connid iTerm2 already forgot). Wait until the reader coroutine has unwound (it
    # discards connid from IT2_LOCALLY_CLOSED in its finally) and confirm no close was emitted.
    await wait_for(lambda: connid not in framer.IT2_LOCALLY_CLOSED)
    check(connid not in framer.IT2_LOCALLY_CLOSED, "reader coroutine unwound after it2close")
    check(len(frames_of_kind("close")) == 0,
          "no duplicate close echoed after iTerm2-initiated it2close: %r" % it2_frames())
    # The client still gets EOF (the connection really did close).
    eof = await asyncio.wait_for(reader.read(1), timeout=2)
    check(eof == b"", "client got EOF after it2close")

    writer.close()
    _reset_server()
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_client_disconnect_emits_close():
    """When the CLIENT (not iTerm2) closes, the framer must emit exactly one %it2 close so
    iTerm2 learns the connection died -- the it2close suppression is only for iTerm2-initiated
    teardown, so a client disconnect must NOT be silenced."""
    print("test_client_disconnect_emits_close")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    try:
        await framer.handle_it2listen("id-listen-cd", [path])
        reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        connid = frames_of_kind("open")[0].split()[1]
        # The client goes away on its own; framer never saw an it2close.
        writer.close()
        await wait_for(lambda: frames_of_kind("close"))
        closes = [f for f in frames_of_kind("close") if f.split()[1] == connid]
        check(len(closes) == 1, "exactly one close on client disconnect: %r" % it2_frames())
        check(connid not in framer.IT2_CONNS, "connection removed from IT2_CONNS")
    finally:
        _reset_server()
        with contextlib.suppress(OSError):
            os.unlink(path)
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_it2close_aborts_stalled_client():
    """it2close on a client that stopped reading must abort (RST), not graceful-close. A
    graceful close defers FIN until the down buffer flushes, which never happens for a stalled
    consumer, so the reader coroutine would hang forever (and leak its IT2_LOCALLY_CLOSED
    flag). Verify the reader unwinds promptly instead."""
    print("test_it2close_aborts_stalled_client")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    writer = None
    try:
        await framer.handle_it2listen("id-listen-ab", [path])
        reader, writer = await asyncio.open_unix_connection(path)  # client never reads
        await wait_for(lambda: frames_of_kind("open"))
        connid = frames_of_kind("open")[0].split()[1]
        # Fill the down buffer so a graceful close() would defer FIN indefinitely.
        big = base64.b64encode(b"x" * (8 * 1024 * 1024)).decode()
        await asyncio.wait_for(framer.handle_it2send("id-send-ab", [connid, big]), timeout=10)
        await framer.handle_it2close("id-close-ab", [connid])
        # With abort() the reader gets EOF and unwinds (discards the flag) despite the stalled
        # buffer; with a graceful close() it would hang and this wait_for would time out.
        unwound = await wait_for(lambda: connid not in framer.IT2_LOCALLY_CLOSED, timeout=5)
        check(unwound, "reader unwound after it2close abort (graceful close would hang)")
        check(connid not in framer.IT2_CONNS, "connection removed from IT2_CONNS")
    finally:
        if writer is not None:
            with contextlib.suppress(Exception):
                writer.close()
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_large_client_output_is_chunked_and_reassembles():
    """A client write larger than IT2_READ_CHUNK must be emitted as several %it2
    data frames (so iTerm2's O(n^2) OSC parser is never handed one huge frame),
    and their concatenation must equal the original bytes."""
    print("test_large_client_output_is_chunked_and_reassembles")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    await framer.handle_it2listen("id-listen3", [path])
    reader, writer = await asyncio.open_unix_connection(path)
    await wait_for(lambda: frames_of_kind("open"))

    payload = bytes((i * 7) & 0xff for i in range(5000))  # > IT2_READ_CHUNK (1024)
    writer.write(payload)
    await writer.drain()

    await wait_for(lambda: sum(len(base64.b64decode(f.split()[3]))
                               for f in frames_of_kind("data")) >= len(payload))
    datas = frames_of_kind("data")
    check(len(datas) >= 2, "large output split into multiple frames: got %d" % len(datas))
    for f in datas:
        chunk = base64.b64decode(f.split()[3])
        check(len(chunk) <= framer.IT2_READ_CHUNK, "each frame within IT2_READ_CHUNK: %d" % len(chunk))
    reassembled = b"".join(base64.b64decode(f.split()[3]) for f in datas)
    check(reassembled == payload, "chunks reassemble to the original bytes")

    writer.close()
    _reset_server()
    with contextlib.suppress(OSError):
        os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_listen_creates_owner_only_socket_dir():
    """The socket must live in an owner-only (0700) directory that framer creates,
    so no other local user can traverse to it (the socket is also 0600)."""
    print("test_listen_creates_owner_only_socket_dir")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    base = tempfile.mkdtemp()
    socket_dir = os.path.join(base, "it2")  # does not exist yet
    path = os.path.join(socket_dir, "s.sock")
    await framer.handle_it2listen("id-dir", [path])
    check(end_status("id-dir") == 0, "listen succeeded: %r" % end_status("id-dir"))
    check(os.path.isdir(socket_dir), "framer created the socket directory")
    dmode = stat.S_IMODE(os.stat(socket_dir).st_mode)
    check(dmode == 0o700, "socket dir is 0700, got %o" % dmode)
    check(os.path.exists(path), "socket file created")
    smode = stat.S_IMODE(os.stat(path).st_mode)
    check(smode == 0o600, "socket file is 0600, got %o" % smode)

    _reset_server()
    with contextlib.suppress(OSError):
        os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_teardown_unlinks_socket():
    """framer must unlink the socket on shutdown so one in a persistent per-user
    directory does not leak across sessions."""
    print("test_teardown_unlinks_socket")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    base = tempfile.mkdtemp()
    path = os.path.join(base, "it2", "s.sock")
    await framer.handle_it2listen("id-td", [path])
    check(os.path.exists(path), "socket exists after listen")

    framer._it2_teardown_socket()
    check(not os.path.exists(path), "socket unlinked after teardown")
    check(framer.IT2_SERVER is None, "server closed after teardown")
    check(framer.IT2_SOCKET_PATH is None, "socket path cleared after teardown")

    _reset_server()
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_chmod_failure_tears_down_and_recovers():
    """If chmod fails after the socket is bound, the server must be torn down and
    the global reset so the socket is not left live/exposed and re-listen works."""
    print("test_chmod_failure_tears_down_and_recovers")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")

    orig_chmod = framer.os.chmod

    # Fail ONLY the post-bind chmod of the socket file, not the pre-bind chmod of its
    # parent directory. Otherwise the failure trips before start_unix_server binds, and the
    # security-relevant branch (tear down an already-bound, possibly-exposed socket) is
    # never exercised -- the assertions would pass for free (nothing bound, nothing created).
    def boom(target, *a, **k):
        if target == path:
            raise OSError("chmod denied")
        return orig_chmod(target, *a, **k)

    framer.os.chmod = boom
    try:
        await framer.handle_it2listen("id-fail", [path])
    finally:
        framer.os.chmod = orig_chmod

    check(end_status("id-fail") == 1, "listen reported failure: %r" % end_status("id-fail"))
    check(framer.IT2_SERVER is None, "server torn down (IT2_SERVER is None) after failure")
    check(not os.path.exists(path), "socket file removed after failure")

    # A subsequent listen with a valid path must succeed: proves the global was
    # reset rather than wedged into a permanent success-returning no-op.
    _frames.clear()
    await framer.handle_it2listen("id-retry", [path])
    check(end_status("id-retry") == 0, "re-listen succeeds: %r" % end_status("id-retry"))
    check(framer.IT2_SERVER is not None, "server running after successful re-listen")

    _reset_server()
    with contextlib.suppress(OSError):
        os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_send_over_buffer_cap_drops_without_blocking():
    """it2send must never block the shared command loop on a stalled consumer: it writes
    without awaiting drain(), and drops the connection only if the unsent buffer grows past
    the cap. Every send returns promptly regardless of whether the peer is reading."""
    print("test_send_over_buffer_cap_drops_without_blocking")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    saved_cap = framer.IT2_WRITE_BUFFER_MAX
    framer.IT2_WRITE_BUFFER_MAX = 256 * 1024  # small so a single big send exceeds it
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    writer = None
    try:
        await framer.handle_it2listen("id-listen2", [path])
        # Connect but never read, so the socket send buffer fills and the framer's unsent
        # buffer grows past the cap.
        _reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        opens = frames_of_kind("open")
        check(len(opens) == 1, "open frame for wedged client: %r" % it2_frames())
        connid = opens[0].split()[1]

        big = base64.b64encode(b"x" * (8 * 1024 * 1024)).decode()

        start = asyncio.get_event_loop().time()
        wedged = False
        for _ in range(8):
            _frames.clear()
            # If a send ever blocked (regressed to awaiting drain), the outer wait_for
            # turns the hang into a bounded failure rather than a hung test process.
            try:
                await asyncio.wait_for(
                    framer.handle_it2send("id-send2", [connid, big]), timeout=10)
            except asyncio.TimeoutError:
                check(False, "handle_it2send blocked >10s (send not fire-and-forget)")
                break
            if connid not in framer.IT2_CONNS:
                wedged = True
                break
        elapsed = asyncio.get_event_loop().time() - start

        check(wedged, "an over-cap send dropped the wedged connection")
        check(connid not in framer.IT2_CONNS, "wedged connection removed from IT2_CONNS")
        check(end_status("id-send2") == 1, "wedged send reported failure: %r" % end_status("id-send2"))
        check(elapsed < 8, "sends stayed bounded (%.2fs)" % elapsed)
    finally:
        framer.IT2_WRITE_BUFFER_MAX = saved_cap
        if writer is not None:
            with contextlib.suppress(Exception):
                writer.close()
        _reset_server()
        with contextlib.suppress(OSError):
            os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_single_large_frame_is_not_treated_as_over_cap():
    """A single down-frame larger than the cap must go through: one frame is bounded memory,
    not a stalled-consumer leak. The cap is sampled BEFORE the write, so a lone big frame onto
    a healthy near-empty buffer is never mistaken for accumulation. Regression guard: sampling
    AFTER the write aborted a healthy client on one oversized line (write() flushes only ~wmem
    synchronously and buffers the rest, with no event-loop turn to drain before the sample)."""
    print("test_single_large_frame_is_not_treated_as_over_cap")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    saved_cap = framer.IT2_WRITE_BUFFER_MAX
    framer.IT2_WRITE_BUFFER_MAX = 256 * 1024  # far smaller than the frame below
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    writer = None
    try:
        await framer.handle_it2listen("id-listen4", [path])
        # A client that never reads: the ONLY thing that could drop this first big send is the
        # (buggy) after-write cap check. With the before-write check the empty buffer passes.
        _reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        connid = frames_of_kind("open")[0].split()[1]

        big = base64.b64encode(b"x" * (8 * 1024 * 1024)).decode()  # 8 MiB, >> cap
        await asyncio.wait_for(framer.handle_it2send("id-send4", [connid, big]), timeout=10)
        check(connid in framer.IT2_CONNS,
              "lone over-cap frame kept the connection: %r" % list(framer.IT2_CONNS))
        check(end_status("id-send4") == 0,
              "lone over-cap send reported success: %r" % end_status("id-send4"))

        # The consumer is now wedged (whole frame unflushed since it never reads). The NEXT
        # send sees an over-cap buffer before writing and drops it: stall protection intact.
        _frames.clear()
        await asyncio.wait_for(framer.handle_it2send("id-send4b", [connid, big]), timeout=10)
        check(connid not in framer.IT2_CONNS, "wedged consumer dropped on its next send")
        check(end_status("id-send4b") == 1, "over-cap wedged send reported failure")
    finally:
        framer.IT2_WRITE_BUFFER_MAX = saved_cap
        if writer is not None:
            with contextlib.suppress(Exception):
                writer.close()
        _reset_server()
        with contextlib.suppress(OSError):
            os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def test_send_over_buffer_cap_aborts_reader_and_emits_close():
    """After an over-cap send drops the connection, the framer must ABORT it (not
    gracefully close): only an abort delivers EOF to the framer's OWN reader coroutine
    (whose socket buffer is full), so it unwinds and emits the `%it2 close` that tells the
    demux the connection died. The client never reads and never disconnects, so the EOF
    must come from the abort."""
    print("test_send_over_buffer_cap_aborts_reader_and_emits_close")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    saved_cap = framer.IT2_WRITE_BUFFER_MAX
    framer.IT2_WRITE_BUFFER_MAX = 256 * 1024
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    writer = None
    try:
        await framer.handle_it2listen("id-listen3", [path])
        # Connect and never read; keep the client open so the EOF that unblocks the
        # framer's reader can only come from the framer aborting the connection itself.
        _reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        connid = frames_of_kind("open")[0].split()[1]

        big = base64.b64encode(b"x" * (8 * 1024 * 1024)).decode()
        for _ in range(8):
            await asyncio.wait_for(
                framer.handle_it2send("id-send3", [connid, big]), timeout=10)
            if connid not in framer.IT2_CONNS:
                break
        check(connid not in framer.IT2_CONNS, "wedged connection dropped from IT2_CONNS")

        # The abort must give the reader coroutine EOF so it finishes and emits close.
        # (With a graceful close() this frame never arrives and the wait times out.)
        await wait_for(lambda: any(f.split()[1] == connid for f in frames_of_kind("close")))
        check(any(f.split()[1] == connid for f in frames_of_kind("close")),
              "reader unwound and emitted %%it2 close: %r" % it2_frames())
    finally:
        framer.IT2_WRITE_BUFFER_MAX = saved_cap
        if writer is not None:
            with contextlib.suppress(Exception):
                writer.close()
        _reset_server()
        with contextlib.suppress(OSError):
            os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


def _make_socket_file(path):
    """Bind then close a unix socket, leaving the socket file behind with no listener --
    mirrors a socket left by a framer that was killed."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.close()


async def test_listen_reclaims_unlocked_sockets():
    """A live framer holds an exclusive advisory lock on <socket>.lock for its whole life;
    the kernel drops it when the process dies (even on SIGKILL). A new it2listen reclaims a
    socket whose lock is free (dead owner) or absent (a leftover predating this scheme) but
    leaves one whose lock a live owner still holds -- race-free, unlike probing by connecting.
    Orphan locks are dropped; non-socket files and the new listen's own lock are preserved."""
    print("test_listen_reclaims_unlocked_sockets")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()
    d = tempfile.mkdtemp()
    held_fd = None
    try:
        # (a) dead owner: socket + a lock file nobody holds.
        dead = os.path.join(d, "dead.sock")
        _make_socket_file(dead)
        open(dead + ".lock", "w").close()
        # (b) legacy leftover: socket with no lock sidecar at all.
        legacy = os.path.join(d, "legacy.sock")
        _make_socket_file(legacy)
        # (c) live owner: socket + a lock we actually hold for the duration of the test.
        live = os.path.join(d, "live.sock")
        _make_socket_file(live)
        held_fd = os.open(live + ".lock", os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(held_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # (d) orphan lock: a lock file whose socket is already gone, unheld.
        orphan_lock = os.path.join(d, "orphan.sock.lock")
        open(orphan_lock, "w").close()
        # (e) a non-socket file must never be touched.
        regular = os.path.join(d, "keep.txt")
        with open(regular, "w") as f:
            f.write("x")

        path = os.path.join(d, "it2.sock")
        await framer.handle_it2listen("id-sweep", [path])

        check(not os.path.exists(dead), "dead-owner socket reclaimed")
        check(not os.path.exists(dead + ".lock"), "dead-owner lock removed")
        check(not os.path.exists(legacy), "legacy lockless socket reclaimed")
        check(not os.path.exists(orphan_lock), "orphan lock removed")
        check(os.path.exists(live), "live socket kept (lock held)")
        check(os.path.exists(live + ".lock"), "live lock kept")
        check(os.path.exists(regular), "non-socket file kept")
        check(os.path.exists(path), "new listen socket bound")
        check(os.path.exists(path + ".lock"), "new listen took its lock")
        check(framer.IT2_LOCK_FD is not None, "new listen holds its lock fd")
        check(framer.IT2_SERVER is not None, "server started")
    finally:
        if held_fd is not None:
            os.close(held_fd)
        _reset_server()
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if ok else "  FAILED")
    return ok


async def run():
    results = []
    for test in (
        test_happy_path,
        test_client_disconnect_emits_close,
        test_it2close_aborts_stalled_client,
        test_large_client_output_is_chunked_and_reassembles,
        test_listen_creates_owner_only_socket_dir,
        test_teardown_unlinks_socket,
        test_chmod_failure_tears_down_and_recovers,
        test_listen_reclaims_unlocked_sockets,
        test_send_over_buffer_cap_drops_without_blocking,
        test_single_large_frame_is_not_treated_as_over_cap,
        test_send_over_buffer_cap_aborts_reader_and_emits_close,
    ):
        results.append(await test())
    ok = all(results)
    print("PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
