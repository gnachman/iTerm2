#!/usr/bin/env python3
"""
Manual test for the Kitty drag-and-drop protocol (OSC 72) inbound handshake.

Run this inside an iTerm2 session (a debug build with the feature). It exercises
the parts wired so far: the query and the accept/offer registration, and prints
whatever the terminal reports back.

    python3 tests/kitty-dnd/probe.py

What it checks:
  - t=q  (query support): a compliant terminal replies with t=q, echoing i=.
  - t=a  (announce accept): no reply expected; it deregisters with t=A before
         exiting so it does not leave the protocol enabled on the shell.

The actual drag-and-drop (dropping files onto the window, dragging out of it)
is AppKit UI and cannot be exercised from a script; use a real drag with
drop_target.py / drag_source.py.
"""

import os
import sys
import termios
import tty
import select


def send(seq: str) -> None:
    sys.stdout.write(seq)
    sys.stdout.flush()


def read_reply(timeout: float = 1.0) -> bytes:
    """Read a single OSC 72 reply (ESC ] 72 ; ... ST/BEL), or b'' on timeout."""
    fd = sys.stdin.fileno()
    out = bytearray()
    deadline_reads = 0
    while True:
        r, _, _ = select.select([fd], [], [], timeout)
        if not r:
            break
        chunk = os.read(fd, 1024)
        if not chunk:
            break
        out += chunk
        # Stop once we see a terminator (ST = ESC \, or BEL).
        if b"\x1b\\" in out or b"\x07" in out:
            break
        deadline_reads += 1
        if deadline_reads > 64:
            break
    return bytes(out)


def main() -> int:
    if not sys.stdin.isatty():
        print("Run this in an interactive terminal.", file=sys.stderr)
        return 2

    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)

        # 1) Query support.
        send("\x1b]72;t=q:i=42\x1b\\")
        reply = read_reply()
        ok_query = b"t=q" in reply and b"i=42" in reply

        # 2) Announce acceptance (no reply expected).
        send("\x1b]72;t=a;text/plain text/uri-list\x1b\\")
        stray = read_reply(timeout=0.3)
    finally:
        # Deregister so we do not leave the protocol enabled on the shell.
        send("\x1b]72;t=A\x1b\\")
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)

    print("\r")
    print("query reply: {!r}".format(reply))
    print("query recognized: {}".format("YES" if ok_query else "NO"))
    print("announce stray reply: {!r}".format(stray if stray else b"(none, expected)"))
    return 0 if ok_query else 1


if __name__ == "__main__":
    sys.exit(main())
