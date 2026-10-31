#!/usr/bin/env python3
# Manual test for issue 13184: mouse motion reports with CSI ? 1003 h.
#
# Sends the same startup sequence Lanterna does (alt screen, 1003, 1005, then a
# cursor-position query) and shows each mouse report it receives. Move the
# pointer over the window: the motion count should climb and the position
# should follow the pointer. Before the fix, clicks were counted but motion
# stayed at 0 until something else (like pressing Command) refreshed tracking.
#
# Press q to quit.

import os
import sys
import termios
import tty

ESC = "\x1b"


def out(s):
    os.write(sys.stdout.fileno(), s.encode())


def read_char(fd):
    # 1005 encodes coordinates as UTF-8, so read whole characters.
    b = os.read(fd, 1)
    if not b:
        return ""
    first = b[0]
    if first >= 0xF0:
        remaining = 3
    elif first >= 0xE0:
        remaining = 2
    elif first >= 0xC0:
        remaining = 1
    else:
        remaining = 0
    while remaining:
        more = os.read(fd, remaining)
        if not more:
            break
        b += more
        remaining -= len(more)
    return b.decode("utf-8", "replace")


def main():
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    motion = 0
    clicks = 0
    try:
        # Same order as Lanterna: alt screen, any-event mouse, UTF-8 coords,
        # save cursor, move far away, ask where the cursor is, restore.
        out(f"{ESC}[?1049h{ESC}[?1003h{ESC}[?1005h"
            f"{ESC}[s{ESC}[5001;5001H{ESC}[6n{ESC}[u")
        out(f"{ESC}[2J{ESC}[H")
        out("Move the mouse. Press q to quit.")
        while True:
            c = read_char(fd)
            if c in ("q", "Q", ""):
                break
            if c != ESC:
                continue
            if read_char(fd) != "[":
                continue
            c = read_char(fd)
            if c != "M":
                # Skip other replies, like the cursor-position report.
                while c and not c.isalpha():
                    c = read_char(fd)
                continue
            cb = ord(read_char(fd)) - 32
            x = ord(read_char(fd)) - 32
            y = ord(read_char(fd)) - 32
            if cb & 32:
                motion += 1
                kind = "motion"
            else:
                clicks += 1
                kind = "button"
            out(f"{ESC}[2;1H{ESC}[2K"
                f"motion={motion} clicks={clicks} last={kind} at {x},{y}")
            out(f"{ESC}[{y};{x}H")
    finally:
        out(f"{ESC}[?1005l{ESC}[?1003l{ESC}[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    print(f"motion reports: {motion}, button reports: {clicks}")


if __name__ == "__main__":
    main()
