#!/usr/bin/env python3
"""Remote `it2` client for iTerm2 SSH integration.

When you are ssh'd into a host via iTerm2's SSH integration, the conductor's
framer.py exports a unix domain socket (path in $IT2_SOCK) that proxies to the
local iTerm2. This tiny stdlib-only client just forwards argv + terminal context
to the local machine, where the *real* it2 command tree (embedded in iTerm2) runs
and dispatches to the API server; stdout/stderr/exit stream back. The client never
builds an API request itself, so it stays trivially in sync with the Swift it2.

Wire protocol (this client <-> framer socket), length-prefixed frames:

    [1 byte type][4 byte big-endian payload length][payload]

Upstream (client -> iTerm2):
    'H' HELLO   json: {nonce, argv, cwd, term, isatty, cols, rows}
    'C' CANCEL  empty  (SIGINT; used by long-running/monitor commands)

Downstream (iTerm2 -> client):
    'O' STDOUT  raw bytes
    'E' STDERR  raw bytes
    'X' EXIT    json: {code}   (last frame; connection then closes)

Requires only the Python standard library and Python 3.7+ (guaranteed present:
the framer this talks to already runs under it).
"""

import json
import os
import signal
import socket
import struct
import sys
import time

HELLO = b"H"
CANCEL = b"C"
STDOUT = ord("O")
STDERR = ord("E")
EXIT = ord("X")

# A declared frame length above this is treated as a local framing desync (a data byte misread
# as a length prefix) and aborted, rather than trying to buffer toward the 4 GiB u32 maximum.
# Generous, because a legitimate down-frame carries one output line, which can be large (e.g.
# `it2 session read` of a very long line); the payload-read timeout below is the real stall
# guard, this just gives an immediate, clear error for an obviously bogus length.
MAX_FRAME_LENGTH = 256 * 1024 * 1024
# Once a header declares a payload length, its bytes should arrive promptly. If the read
# stalls mid-payload (a desync, or an unresponsive peer), time out and surface an error instead
# of blocking forever on a recv that PEP 475 keeps retrying (which also swallows the first
# Ctrl-C). This deliberately does NOT apply to the idle wait for the next frame's header -- a
# long-running `monitor --follow` legitimately idles between frames.
PAYLOAD_READ_TIMEOUT = 30

# True while the main thread is inside send_frame. it2.py spawns no threads, so the only
# possible re-entry is the SIGINT handler firing on this same thread while a frame is being
# sent. on_sigint checks this flag and returns early when it is set, so it never re-enters
# send_frame -- which is why no lock is needed: the send path is only ever touched by one
# thread, and that thread never re-enters it.
_sending = False


def send_frame(sock, ftype, payload=b""):
    global _sending
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    header = ftype + struct.pack(">I", len(payload))
    # Set the flag before the send so the signal handler can never observe "not sending"
    # while we are in the middle of writing a frame.
    _sending = True
    try:
        sock.sendall(header + payload)
    finally:
        _sending = False


def recv_exact(sock, n, deadline=None):
    # If `deadline` (a time.monotonic() timestamp) is given, the WHOLE read must finish by then:
    # each recv gets the remaining budget as its timeout, so a slow trickle cannot keep resetting
    # a per-recv idle timer. Without a deadline the socket's current timeout applies (the callers'
    # header read leaves it unset -> blocking, which idling between frames needs).
    chunks = []
    remaining = n
    while remaining > 0:
        if deadline is not None:
            budget = deadline - time.monotonic()
            if budget <= 0:
                raise socket.timeout("payload read deadline exceeded")
            sock.settimeout(budget)
        chunk = sock.recv(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_frame(sock):
    # The header read has no timeout on purpose: idling between frames is normal for a
    # streaming command (monitor --follow), so a stalled next-frame wait must not abort.
    header = recv_exact(sock, 5)
    if header is None:
        return None, None
    ftype = header[0]
    length = struct.unpack(">I", header[1:5])[0]
    if length > MAX_FRAME_LENGTH:
        eprint("it2: framing error (declared frame length %d exceeds maximum); aborting.\n" % length)
        return None, None
    if not length:
        return ftype, b""
    # The payload, unlike the next-frame wait, should arrive promptly; bound the WHOLE read with
    # a single deadline. A per-recv idle timeout would be reset by every chunk, so a slow-trickle
    # desync (small frames misread as payload bytes, each arriving <timeout apart) would never
    # surface -- the deadline bounds the total read time regardless of chunk pacing.
    deadline = time.monotonic() + PAYLOAD_READ_TIMEOUT
    try:
        payload = recv_exact(sock, length, deadline=deadline)
    except (socket.timeout, TimeoutError, OSError):
        eprint("it2: framing error (stalled reading a %d-byte frame payload); aborting.\n" % length)
        payload = None
    finally:
        try:
            sock.settimeout(None)
        except OSError:
            pass
    if payload is None:
        return None, None
    return ftype, payload


def terminal_size():
    # sys.stdout is None when stdout is closed before exec (e.g. `it2 foo >&-`), so
    # sys.stdout.fileno() raises AttributeError. A stream closed in-process raises
    # ValueError, and other stream failures OSError. Any of these means "no terminal".
    try:
        size = os.get_terminal_size(sys.stdout.fileno())
        return size.columns, size.lines
    except (AttributeError, OSError, ValueError):
        return 0, 0


def safe_getcwd():
    # FileNotFoundError (an OSError) if the working directory was removed.
    try:
        return os.getcwd()
    except OSError:
        return ""


def safe_isatty():
    # sys.stdout may be None (closed before exec) -> AttributeError; closed in-process
    # -> ValueError; other failures -> OSError.
    try:
        return sys.stdout.isatty()
    except (AttributeError, ValueError, OSError):
        return False


# Streams that have taken at least one successful write. A write failure on such a
# stream is a mid-stream break (a downstream consumer that exited -> broken pipe, or a
# full disk) that should stop us like SIGPIPE on a local pipeline; a failure on a stream
# that never worked (>&-, closed before exec) is tolerated and dropped as before.
_usable_streams = set()


def write_raw(stream, payload):
    # Returns True to keep going (wrote, or harmlessly dropped on a never-usable stream),
    # False if the stream broke so the caller stops like SIGPIPE.
    try:
        stream.buffer.write(payload)
        stream.buffer.flush()
        _usable_streams.add(id(stream))
        return True
    except (BrokenPipeError, ConnectionResetError):
        # A broken pipe / reset means a real downstream consumer existed and went away (e.g.
        # `it2 cmd | head -c0` or a pager quit closing the read end before our FIRST write).
        # Treat that as broke even with no prior successful write -- otherwise the _usable_
        # streams heuristic below would misread it as "never usable, drop harmlessly", silently
        # discarding all output, never sending CANCEL, and returning the wrong exit code.
        return False
    except (AttributeError, ValueError, OSError):
        # stream is None / closed in-process (AttributeError/ValueError), or a non-pipe OSError
        # like EBADF from `>&-` / closed-before-exec. Tolerate a failure on a stream that never
        # worked (drop, keep going); only a previously-good stream breaking stops us.
        return id(stream) not in _usable_streams


def eprint(message):
    # Same None/closed-stream tolerance for our own diagnostics (e.g. `it2 foo 2>&-`).
    try:
        sys.stderr.write(message)
    except (AttributeError, ValueError, OSError):
        pass


def main():
    sock_path = os.environ.get("IT2_SOCK")
    if not sock_path:
        eprint("it2: not running under iTerm2 SSH integration (IT2_SOCK is unset).\n")
        return 2

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_path)
    except OSError as e:
        eprint("it2: cannot reach iTerm2 (%s): %s\n" % (sock_path, e))
        return 2
    except KeyboardInterrupt:
        return 130

    cols, rows = terminal_size()
    hello = {
        "nonce": os.environ.get("IT2_NONCE", ""),
        "argv": sys.argv[1:],
        "cwd": safe_getcwd(),
        "term": os.environ.get("TERM", ""),
        "isatty": safe_isatty(),
        "cols": cols,
        "rows": rows,
    }
    try:
        send_frame(sock, HELLO, json.dumps(hello))
    except OSError as e:
        eprint("it2: connection lost: %s\n" % e)
        return 2
    except KeyboardInterrupt:
        return 130

    # First Ctrl-C asks the server to cancel; restoring the default handler means
    # a second Ctrl-C kills the client for real, so an unanswered or hung server
    # can never make it2 uninterruptible.
    def on_sigint(_signum, _frame):
        signal.signal(signal.SIGINT, signal.SIG_DFL)  # a second Ctrl-C is fatal
        if _sending:
            # A frame is already being sent on this (the main) thread -- e.g. the broken-
            # pipe path is sending CANCEL. Sending again now would re-enter the non-
            # reentrant send path and deadlock (or corrupt the in-flight frame). Skip it:
            # SIG_DFL is restored, and a CANCEL is already on its way in the send case.
            return
        try:
            # recv_exact may have left a short payload-read timeout on this shared socket; clear
            # it so this CANCEL's sendall is never swallowed by an inherited read timeout (which
            # would silently drop the user's cancel while the connection is alive).
            sock.settimeout(None)
            send_frame(sock, CANCEL)
        except OSError:
            pass

    signal.signal(signal.SIGINT, on_sigint)

    exit_code = 0
    saw_exit = False
    broken = False
    while True:
        ftype, payload = recv_frame(sock)
        if ftype is None:
            break
        if ftype == STDOUT:
            if not write_raw(sys.stdout, payload):
                broken = True
                break
        elif ftype == STDERR:
            if not write_raw(sys.stderr, payload):
                broken = True
                break
        elif ftype == EXIT:
            saw_exit = True
            try:
                obj = json.loads(payload.decode("utf-8"))
                # Tolerate a payload that is valid JSON but not an object (e.g. a
                # bare number/string/null): .get would raise AttributeError.
                exit_code = int(obj.get("code", 0)) if isinstance(obj, dict) else 0
            except (ValueError, TypeError):
                exit_code = 0
            break

    if broken:
        # A previously-good output stream broke mid-stream (downstream consumer exited,
        # like `it2 monitor -f | head`, or a full disk). Mirror a local pipeline's SIGPIPE:
        # ask the server to cancel a still-running command, then exit 128+SIGPIPE(13).
        try:
            send_frame(sock, CANCEL)
        except OSError:
            pass
        try:
            sock.close()
        except OSError:
            pass
        return 141

    try:
        sock.close()
    except OSError:
        pass

    if not saw_exit:
        # EXIT is contractually the last frame; a disconnect without it means the
        # command did not complete normally (server crash, killed job, reset).
        eprint("it2: connection closed before completion.\n")
        return 2
    return exit_code


def _silence_std_stream_flush():
    # Python flushes stdout/stderr during interpreter shutdown. If a downstream consumer
    # (e.g. `it2 monitor -f | head`) has exited, that flush hits the now-broken pipe again
    # and prints a spurious "Exception ignored in ... BrokenPipeError" traceback, even though
    # main() already handled the break and we are exiting cleanly. Flush each stream now,
    # swallowing the error, and point its fd at /dev/null so the shutdown flush stays silent.
    # (See the note on SIGPIPE in the Python docs.)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except (BrokenPipeError, ValueError, OSError):
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), stream.fileno())
            except (OSError, ValueError, AttributeError):
                pass


if __name__ == "__main__":
    try:
        code = main()
    except KeyboardInterrupt:
        # A Ctrl-C in the narrow window before main() installs its SIGINT handler (or after it
        # restores SIG_DFL) reaches here as an uncaught KeyboardInterrupt. Exit a clean 130
        # like a shell-interrupted process instead of dumping a traceback with status 1.
        code = 130
    _silence_std_stream_flush()
    sys.exit(code)
