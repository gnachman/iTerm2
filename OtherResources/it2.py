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
import threading

HELLO = b"H"
CANCEL = b"C"
STDOUT = ord("O")
STDERR = ord("E")
EXIT = ord("X")

_send_lock = threading.Lock()


def send_frame(sock, ftype, payload=b""):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    header = ftype + struct.pack(">I", len(payload))
    with _send_lock:
        sock.sendall(header + payload)


def recv_exact(sock, n):
    chunks = []
    remaining = n
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_frame(sock):
    header = recv_exact(sock, 5)
    if header is None:
        return None, None
    ftype = header[0]
    length = struct.unpack(">I", header[1:5])[0]
    payload = recv_exact(sock, length) if length else b""
    if payload is None:
        return None, None
    return ftype, payload


def terminal_size():
    try:
        size = os.get_terminal_size(sys.stdout.fileno())
        return size.columns, size.lines
    except OSError:
        return 0, 0


def main():
    sock_path = os.environ.get("IT2_SOCK")
    if not sock_path:
        sys.stderr.write("it2: not running under iTerm2 SSH integration (IT2_SOCK is unset).\n")
        return 2

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_path)
    except OSError as e:
        sys.stderr.write("it2: cannot reach iTerm2 (%s): %s\n" % (sock_path, e))
        return 2
    except KeyboardInterrupt:
        return 130

    cols, rows = terminal_size()
    hello = {
        "nonce": os.environ.get("IT2_NONCE", ""),
        "argv": sys.argv[1:],
        "cwd": os.getcwd(),
        "term": os.environ.get("TERM", ""),
        "isatty": sys.stdout.isatty(),
        "cols": cols,
        "rows": rows,
    }
    try:
        send_frame(sock, HELLO, json.dumps(hello))
    except OSError as e:
        sys.stderr.write("it2: connection lost: %s\n" % e)
        return 2
    except KeyboardInterrupt:
        return 130

    # First Ctrl-C asks the server to cancel; restoring the default handler means
    # a second Ctrl-C kills the client for real, so an unanswered or hung server
    # can never make it2 uninterruptible.
    def on_sigint(_signum, _frame):
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        try:
            send_frame(sock, CANCEL)
        except OSError:
            pass

    signal.signal(signal.SIGINT, on_sigint)

    exit_code = 0
    saw_exit = False
    while True:
        ftype, payload = recv_frame(sock)
        if ftype is None:
            break
        if ftype == STDOUT:
            sys.stdout.buffer.write(payload)
            sys.stdout.buffer.flush()
        elif ftype == STDERR:
            sys.stderr.buffer.write(payload)
            sys.stderr.buffer.flush()
        elif ftype == EXIT:
            saw_exit = True
            try:
                exit_code = int(json.loads(payload.decode("utf-8")).get("code", 0))
            except (ValueError, TypeError):
                exit_code = 0
            break

    try:
        sock.close()
    except OSError:
        pass

    if not saw_exit:
        # EXIT is contractually the last frame; a disconnect without it means the
        # command did not complete normally (server crash, killed job, reset).
        sys.stderr.write("it2: connection closed before completion.\n")
        return 2
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
