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
import importlib.util
import os
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
    await wait_for(lambda: frames_of_kind("close"))
    check(len(frames_of_kind("close")) >= 1, "close frame emitted: %r" % it2_frames())

    writer.close()
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

    def boom(*a, **k):
        raise OSError("chmod denied")

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


async def test_send_drain_timeout_does_not_block_loop():
    """A client that never reads must not let it2send block the command loop
    forever: the send must return bounded and drop the wedged connection."""
    print("test_send_drain_timeout_does_not_block_loop")
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print("  FAIL:", msg)

    _frames.clear()
    _reset_server()

    saved_timeout = framer.IT2_DRAIN_TIMEOUT
    framer.IT2_DRAIN_TIMEOUT = 0.3
    d = tempfile.mkdtemp()
    path = os.path.join(d, "it2.sock")
    reader = writer = None
    try:
        await framer.handle_it2listen("id-listen2", [path])
        # Connect but never read, so the socket send buffer fills and stays full.
        reader, writer = await asyncio.open_unix_connection(path)
        await wait_for(lambda: frames_of_kind("open"))
        opens = frames_of_kind("open")
        check(len(opens) == 1, "open frame for wedged client: %r" % it2_frames())
        connid = opens[0].split()[1]

        # Comfortably larger than any socket send buffer: drain() can never
        # complete while the peer never reads.
        big = base64.b64encode(b"x" * (8 * 1024 * 1024)).decode()

        start = asyncio.get_event_loop().time()
        wedged = False
        for _ in range(8):
            _frames.clear()
            try:
                # If drain() regressed to unbounded, this hangs; the outer
                # wait_for converts a regression into a bounded failure, not a
                # hung test process.
                await asyncio.wait_for(
                    framer.handle_it2send("id-send2", [connid, big]), timeout=10
                )
            except asyncio.TimeoutError:
                check(False, "handle_it2send blocked >10s (drain not bounded)")
                break
            if connid not in framer.IT2_CONNS:
                wedged = True
                break
        elapsed = asyncio.get_event_loop().time() - start

        check(wedged, "a wedged send timed out and dropped the connection")
        check(connid not in framer.IT2_CONNS, "wedged connection removed from IT2_CONNS")
        check(end_status("id-send2") == 1, "wedged send reported failure: %r" % end_status("id-send2"))
        # Bounded well under the 30s production default and nowhere near forever.
        check(elapsed < 8, "sends stayed bounded (%.2fs)" % elapsed)
    finally:
        framer.IT2_DRAIN_TIMEOUT = saved_timeout
        if writer is not None:
            with contextlib.suppress(Exception):
                writer.close()
        _reset_server()
        with contextlib.suppress(OSError):
            os.unlink(path)
    print("  PASS" if ok else "  FAILED")
    return ok


async def run():
    results = []
    for test in (
        test_happy_path,
        test_chmod_failure_tears_down_and_recovers,
        test_send_drain_timeout_does_not_block_loop,
    ):
        results.append(await test())
    ok = all(results)
    print("PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
