#!/usr/bin/env python3
"""Show the raw bytes iTerm2 sends under the Kitty keyboard protocol.

Repro for issue 12922 (Caps Lock toggle inserts 'A').

Run inside iTerm2:
    python3 tests/kitty_capslock_bytes.py

It enables the Kitty progressive enhancements (including "report all keys
as escape codes"), then echoes every byte it receives. Focus this terminal
and toggle Caps Lock.

Buggy output:  bytes: b'\x1b[65u'      (65 == 'A')
Fixed output:  bytes: b'\x1b[57358;65u' (press) and a release on toggle off
"""

import sys
import os
import termios
import tty

# Push flags: 1 disambiguate | 2 report-event-types | 4 report-alternate-keys
#             | 8 report-all-keys-as-escape-codes | 16 report-associated-text
ENABLE = "\x1b[>15u"
DISABLE = "\x1b[<u"


def main():
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        os.write(fd, ENABLE.encode())
        os.write(fd, b"Toggle Caps Lock. Press 'q' to quit.\r\n")
        while True:
            data = os.read(fd, 64)
            if not data or data == b"q":
                break
            os.write(fd, b"bytes: %r\r\n" % data)
    finally:
        os.write(fd, DISABLE.encode())
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
