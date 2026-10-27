#!/usr/bin/env python3
"""Show tmux queueing a flooding pane without limit for a control client that briefly stops reading.

A control client stands in for iTerm2: tmux -C runs on a pty, with pause-after set as iTerm2
sets it, and a pane runs `yes`. The script reads the client's output for a while, stops reading
for a few seconds, and repeats, sampling the tmux server's memory at the end of each stop.

Expected: while the client isn't reading, tmux stops reading the pane once its write buffer to the
client holds CONTROL_BUFFER_LOW (512) bytes, so the server's memory stays flat. Bug: if that
buffer holds fewer than 512 bytes when the pty fills, the pane stays "on" and tmux keeps reading it
into per-pane blocks that nothing drains until the client reads again, so memory jumps by many MB
in a single stop.

Uses a private server (-L), so it doesn't touch your tmux sessions.
Usage: tmux-control-backlog.py [--tmux PATH] [--cycles 20] [--read 1.0] [--stall 2.0]
"""
import argparse
import os
import pty
import select
import subprocess
import time
import tty

ap = argparse.ArgumentParser()
ap.add_argument("--tmux", default="tmux")
ap.add_argument("--cycles", type=int, default=20)
ap.add_argument("--read", type=float, default=1.0, help="seconds to read each cycle")
ap.add_argument("--stall", type=float, default=2.0, help="seconds to stop reading each cycle")
ap.add_argument("--limit-mb", type=float, default=1500, help="stop early if the server grows past this")
args = ap.parse_args()

sock = f"backlog-repro-{os.getpid()}"
tmux = [args.tmux, "-L", sock, "-f", "/dev/null"]


def server_rss_mb():
    pid = subprocess.run(tmux + ["display", "-p", "#{pid}"], capture_output=True, text=True).stdout.strip()
    rss = subprocess.run(["ps", "-o", "rss=", "-p", pid], capture_output=True, text=True).stdout.strip()
    return int(rss or 0) / 1024


def read_for(fd, seconds):
    """Read and discard the client's output for `seconds`; returns the byte count."""
    total = 0
    deadline = time.monotonic() + seconds
    while (left := deadline - time.monotonic()) > 0:
        ready, _, _ = select.select([fd], [], [], left)
        if ready:
            try:
                total += len(os.read(fd, 65536))
            except OSError:
                break
    return total


master, slave = pty.openpty()
tty.setraw(slave)
client = subprocess.Popen(tmux + ["-C", "new-session", "-x", "200", "-y", "50", "yes"],
                          stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
try:
    read_for(master, 0.5)
    os.write(master, b"refresh-client -f pause-after=120\n")
    print(f"tmux {subprocess.run(tmux + ['-V'], capture_output=True, text=True).stdout.strip()}, "
          f"cycles of {args.read}s reading then {args.stall}s not reading")
    baseline = server_rss_mb()
    print(f"server RSS at start: {baseline:.1f} MB")
    worst = 0.0
    for i in range(args.cycles):
        got = read_for(master, args.read)
        before = server_rss_mb()
        time.sleep(args.stall)
        after = server_rss_mb()
        worst = max(worst, after - baseline)
        flag = "   <-- grew while the client wasn't reading" if after - before > 5 else ""
        print(f"cycle {i + 1:2}: read {got / 1e6:6.2f} MB, server RSS {before:7.1f} -> {after:7.1f} MB{flag}")
        if after > args.limit_mb:
            print("stopping early: the server is past --limit-mb")
            break
    print(f"largest growth over the start: {worst:.1f} MB")
finally:
    subprocess.run(tmux + ["kill-server"], capture_output=True)
    client.kill()
    client.wait()
    os.close(master)
