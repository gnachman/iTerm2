#!/usr/bin/env python3
# Adapted from the reproducer attached to issue 13141 by its reporter.
"""Emulate a TUI that repaints the whole screen (Claude Code / tmux style).

Waits until the control file contains "go", then writes full-screen colored
frames at the requested byte rate until the control file says "stop" or the
deadline passes.
Usage: flood.py CTL_FILE RATE_KBPS FPS MAX_SECONDS [sync|cells]
  cells: mimic tmux 3.8 relaying an idle opencode: each frame rewrites one full
         line where every cell carries its own truecolor fg+bg (RATE_KBPS is
         ignored; the rate follows from width x FPS).
"""
import random
import shutil
import sys
import time

ctl, rate_kbps, fps, max_s = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
style = sys.argv[5] if len(sys.argv) > 5 else "words"
use_sync = style == "sync"


def state():
    try:
        with open(ctl) as f:
            return f.read().strip()
    except OSError:
        return ""


out = sys.stdout.buffer
out.write(b"\x1b[2J\x1b[Hflood: waiting for 'go' in " + ctl.encode() + b"\n")
out.flush()
deadline = time.monotonic() + max_s
while state() != "go":
    if state() == "stop" or time.monotonic() > deadline:
        sys.exit(0)
    time.sleep(0.2)

words = "the quick brown fox jumps over lazy dog Thinking Reading Bash Edit tokens esc to interrupt".split()
frame_bytes = int(rate_kbps * 1024 / fps)
period = 1.0 / fps
next_t = time.monotonic()
frame_no = 0
sent = 0
t0 = time.monotonic()
while time.monotonic() < deadline:
    if frame_no % int(fps) == 0 and state() != "go":
        break
    cols, rows = shutil.get_terminal_size((120, 40))
    if style == "cells":
        phase = frame_no % 64
        cells = []
        for x in range(248):  # opencode pane width in the real case; autowrap off keeps it on one row
            v = (x * 4 + phase * 8) % 256
            cells.append(f"\x1b[38;2;{v};{(v * 3) % 256};{255 - v}m\x1b[48;2;{v // 8};{v // 10};{v // 6}m{chr(0x41 + x % 26)}")
        data = ("\x1b[?7l\x1b[?25l\x1b[2;1H" + "".join(cells) + f"\x1b[39m\x1b[49m\x1b[?7h\x1b[{rows};1H\x1b[?25h").encode()
        out.write(data)
        out.flush()
        sent += len(data)
        frame_no += 1
        next_t += period
        delay = next_t - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        else:
            next_t = time.monotonic()
        continue
    parts = [b"\x1b[?2026h" if use_sync else b"", b"\x1b[?25l\x1b[H"]
    size = 0
    row = 1
    while size < frame_bytes:
        line = []
        width = 0
        while width < cols - 12:
            w = random.choice(words)
            r, g, b = random.randrange(256), random.randrange(256), random.randrange(256)
            line.append(f"\x1b[38;2;{r};{g};{b}m{'' if random.random() < .7 else chr(0x1b) + '[1m'}{w}\x1b[0m ")
            width += len(w) + 1
        s = f"\x1b[{row};1H" + "".join(line) + "\x1b[K"
        parts.append(s.encode())
        size += len(s)
        row = row % rows + 1
    parts.append(f"\x1b[{rows};1H\x1b[7m frame {frame_no} {sent / max(time.monotonic() - t0, 1e-3) / 1024:.0f} KB/s \x1b[0m".encode())
    if use_sync:
        parts.append(b"\x1b[?2026l")
    data = b"".join(parts)
    out.write(data)
    out.flush()
    sent += len(data)
    frame_no += 1
    next_t += period
    delay = next_t - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    else:
        next_t = time.monotonic()
with open(ctl + ".rate", "w") as f:
    f.write(f"{sent / max(time.monotonic() - t0, 1e-3) / 1024:.1f} KB/s over {time.monotonic() - t0:.1f} s, {frame_no} frames\n")
out.write(b"\x1b[0m\x1b[?25h\x1b[2J\x1b[Hflood finished\n")
out.flush()
