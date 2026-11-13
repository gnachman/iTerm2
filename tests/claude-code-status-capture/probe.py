# Sends the OSC 7501 feature query to the terminal and prints what comes back within 3 seconds.
import os, select, sys, termios, time, tty
saved = termios.tcgetattr(0)
tty.setraw(0)
try:
    os.write(1, b"\x1b]7501;?\x1b\\")
    got = b""
    end = time.time() + 3
    while time.time() < end:
        r, _, _ = select.select([0], [], [], end - time.time())
        if not r:
            break
        got += os.read(0, 1024)
        if got.endswith(b"\x1b\\") or got.endswith(b"\x07"):
            break
finally:
    termios.tcsetattr(0, termios.TCSAFLUSH, saved)
print("reply:", repr(got))
