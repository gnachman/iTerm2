#!/usr/bin/env python3
"""Records the raw bytes a program writes to an 80x24 terminal, for the twin session tests.

usage: record_pty.py OUTPUT SECONDS SCRIPT -- COMMAND [ARG...]

SCRIPT is a list of "delay:text" steps separated by "|". Each step waits `delay` seconds and
then types `text`. In text, \\r is Return, \\e is Escape, and \\xNN is a byte.
Nothing answers the program's terminal queries.
"""
import codecs
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time


def main():
    separator = sys.argv.index("--")
    output, seconds, script = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    command = sys.argv[separator + 1:]
    steps = []
    at = 0.0
    for step in filter(None, script.split("|")):
        delay, _, text = step.partition(":")
        at += float(delay)
        text = text.replace("\\e", "\\x1b")
        steps.append((at, codecs.decode(text, "unicode_escape").encode("latin-1")))

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execvp(command[0], command)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    start = time.monotonic()
    with open(output, "wb") as out:
        while True:
            elapsed = time.monotonic() - start
            if elapsed >= seconds:
                break
            while steps and steps[0][0] <= elapsed:
                os.write(fd, steps.pop(0)[1])
            readable, _, _ = select.select([fd], [], [], 0.05)
            if fd in readable:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                out.write(data)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass


if __name__ == "__main__":
    main()
