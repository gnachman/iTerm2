#!/usr/bin/env python3
# Adapted from the reproducer attached to issue 13141 by its reporter.
"""Latency probe run inside an iTerm2 session.

- Logs the arrival time (CLOCK_MONOTONIC, shared system-wide on macOS) of every
  space typed into this session -> keystroke-to-pty latency when paired with
  run_experiment.py's send times.
- Sends DSR (CSI 6n) every 250 ms and logs the round trip -> latency of this
  session's output-parsing path.
- Reports focus in/out (mode 1004) to FOCUS_FILE so the injector only types
  while this session is the key session.
Usage: probe.py OUT_DIR MAX_SECONDS
"""
import os
import select
import sys
import termios
import time
import tty

out_dir, max_s = sys.argv[1], float(sys.argv[2])
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
keys = open(os.path.join(out_dir, "probe-keys.log"), "a", buffering=1)
dsr = open(os.path.join(out_dir, "probe-dsr.log"), "a", buffering=1)
focus_path = os.path.join(out_dir, "probe-focus")
stop_path = os.path.join(out_dir, "probe-stop")


def now():
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def set_focus(v):
    with open(focus_path + ".tmp", "w") as f:
        f.write(v)
    os.replace(focus_path + ".tmp", focus_path)


tty.setraw(fd)
try:
    os.write(1, b"\x1b[2J\x1b[Hlatency probe - do not touch the keyboard or switch windows\r\n\x1b[?1004h")
    set_focus("unknown")
    deadline = time.monotonic() + max_s
    next_dsr = time.monotonic()
    dsr_sent = None
    buf = b""
    n = 0
    while time.monotonic() < deadline and not os.path.exists(stop_path):
        if dsr_sent is None and time.monotonic() >= next_dsr:
            dsr_sent = now()
            os.write(1, b"\x1b[6n")
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            continue
        data = os.read(fd, 4096)
        t = now()
        buf += data
        while buf:
            if buf.startswith(b"\x1b[I"):
                set_focus("in"); buf = buf[3:]
            elif buf.startswith(b"\x1b[O"):
                set_focus("out"); buf = buf[3:]
            elif buf.startswith(b"\x1b["):
                end = next((i for i in range(2, len(buf)) if 0x40 <= buf[i] <= 0x7e), None)
                if end is None:
                    break
                if buf[end:end + 1] == b"R" and dsr_sent is not None:
                    dsr.write(f"{dsr_sent} {t} {(t - dsr_sent) / 1e6:.3f}\n")
                    dsr_sent = None
                    next_dsr = time.monotonic() + 0.25
                buf = buf[end + 1:]
            elif buf[:1] == b"\x1b":
                if len(buf) < 3:
                    break
                buf = buf[1:]
            else:
                ch = buf[:1]
                buf = buf[1:]
                if ch == b" ":
                    n += 1
                    keys.write(f"{t}\n")
                    os.write(1, b".")
                elif ch in (b"q", b"\x03"):
                    raise SystemExit
finally:
    os.write(1, b"\x1b[?1004l\r\nprobe finished\r\n")
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    set_focus("gone")
