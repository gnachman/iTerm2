#!/usr/bin/env python3
# Adapted from the reproducer attached to issue 13141 by its reporter.
"""Measure iTerm2 keystroke latency in an idle session while other sessions flood output.

Opens (via `open -a iTerm`) N paused flood sessions and one probe session, then
for each phase enables k floods, injects spaces into iTerm2 with
CGEventPostToPid and pairs send times with the probe's arrival times.
Spaces are only sent while the probe reports focus-in (mode 1004), so a stray
key can reach another session only in the race window of a focus change.
Usage: run_experiment.py OUT_ROOT [--app PATH] [--pid PID] [--phases 0,1,3,6] [--rate 900] [--fps 20]
                         [--style words|sync|cells]
--app opens the sessions in that app bundle (default "iTerm"), for driving a particular build.
--pid is the process to post keys to and measure (default: the only process named iTerm2).

Needs permission to post events. Don't touch the keyboard or switch windows while it runs. For
example:
    python3 run_experiment.py OUT_DIR --rate 2000 --phases 0,3,9 --keys 80 --sample 3
Results: OUT_DIR/run-*/run.log has one line per phase (key latency, DSR round trips, CPU, thread
count, memory).
--exec-stats FILE adds iTerm2's token execution stats for each phase (how long joins waited for a
session, and what fraction of execution time was overhead). iTerm2 must be writing them to FILE,
set in the defaults domain the build uses (com.googlecode.iterm2 for a normal install):
    defaults write com.googlecode.iterm2 NoSyncTokenExecutionStatsFile /tmp/exec-stats.txt
"""
import argparse
import os
import re
import statistics
import subprocess
import time

import ctypes
import ctypes.util

_cg = ctypes.CDLL(ctypes.util.find_library("ApplicationServices"))
_cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
_cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
_cg.CGEventPostToPid.argtypes = [ctypes.c_int, ctypes.c_void_p]
_cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
_cf.CFRelease.argtypes = [ctypes.c_void_p]


def post_key(pid, keycode, down):
    ev = _cg.CGEventCreateKeyboardEvent(None, keycode, down)
    _cg.CGEventPostToPid(pid, ev)
    _cf.CFRelease(ev)


def cpu_seconds(pid):
    """User plus system CPU time of a process, from ps (e.g. "1:02.34" or "1:00:02.34")."""
    text = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    total = 0.0
    for part in text.split(":"):
        total = total * 60 + float(part)
    return total


def thread_count(pid):
    """Number of threads in a process, from ps -M (one line per thread plus a header)."""
    text = subprocess.run(["ps", "-M", "-p", str(pid)], capture_output=True, text=True).stdout
    return max(0, len(text.strip().splitlines()) - 1)


def rss_mb(pid):
    """Resident memory of a process in MB, from ps."""
    text = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(text or 0) / 1024


def complete_blocks(path):
    """The blocks of token execution stats iTerm2 has finished writing to path."""
    try:
        blocks = open(path).read().split("start=")[1:]
    except OSError:
        return []
    return [block for block in blocks if block.endswith("\n")]  # the last may still be being written


def block_end(block):
    m = re.match(r"[0-9.]+ end=([0-9.]+)", block)
    return float(m.group(1)) if m else 0.0


def wait_for_exec_stats(path, end, timeout=10):
    """Waits until iTerm2 has written the block covering time end. It writes one a second."""
    deadline = time.time() + timeout
    while not any(block_end(block) >= end for block in complete_blocks(path)):
        if time.time() > deadline:
            say(f"warning: no token execution stats cover the end of the phase in {path}")
            return
        time.sleep(0.1)


def exec_stats(path, start, end):
    """Summarizes the token execution stats iTerm2 wrote once a second during a phase.

    Each block starts with "start=S end=E", the interval it covers. A block counts toward the phase
    if it began during the phase, so the one covering the time before the phase is left out and the
    one written just after the phase ends is kept."""
    kept = []
    for block in complete_blocks(path):
        try:
            block_start = float(block.split(" ", 1)[0])
        except ValueError:
            continue
        if start <= block_start < end:
            kept.append(block)
    text = "\n".join(kept)
    overhead = busy = 0.0
    waits = yields = 0
    join_p50 = []
    join_p95 = []
    join_max = 0.0
    number = r"([0-9.]+)"
    for m in re.finditer(r"permits " + number + r"ms, other " + number + r"ms, tokens " + number + r"ms, high-pri " + number + "ms", text):
        permits, other, tokens, high = (float(x) for x in m.groups())
        overhead += permits + other
        busy += permits + other + tokens + high
    for m in re.finditer(r"Waits for a permit: (\d+), slice yields: (\d+)", text):
        waits += int(m.group(1))
        yields += int(m.group(2))
    for m in re.finditer(r"Join wait: p50=" + number + r"ms p95=" + number + r"ms max=" + number + "ms", text):
        join_p50.append(float(m.group(1)))
        join_p95.append(float(m.group(2)))
        join_max = max(join_max, float(m.group(3)))
    return dict(overhead_frac=overhead / busy if busy else float("nan"),
                waits=waits, yields=yields,
                join_p50=statistics.median(join_p50) if join_p50 else float("nan"),
                join_p95=max(join_p95) if join_p95 else float("nan"),
                join_max=join_max if join_p50 else float("nan"))


TOOLS = os.path.dirname(os.path.abspath(__file__))
SPACE_KEYCODE = 49

ap = argparse.ArgumentParser()
ap.add_argument("out_root")
ap.add_argument("--app", default="iTerm", help="app to open sessions in, passed to open -a")
ap.add_argument("--pid", type=int, default=0, help="iTerm2 process id (default: the only one named iTerm2)")
ap.add_argument("--phases", default="0,1,3,6")
ap.add_argument("--rate", type=float, default=900, help="KB/s per flood session")
ap.add_argument("--fps", type=float, default=20)
ap.add_argument("--style", default="words", choices=["words", "sync", "cells"], help="flood.py frame style")
ap.add_argument("--keys", type=int, default=40)
ap.add_argument("--ignore-focus", action="store_true",
                help="post keys even without a focus report from the probe (keys that land elsewhere time out)")
ap.add_argument("--gap", type=float, default=0.15)
ap.add_argument("--sample", type=float, default=3, help="seconds of /usr/bin/sample per phase, 0 = off")
ap.add_argument("--exec-stats", default="", help="file iTerm2 writes token execution stats to; reported per phase")
args = ap.parse_args()

phases = [int(x) for x in args.phases.split(",")]
nflood = max(phases)
run = os.path.join(os.path.abspath(args.out_root), time.strftime("run-%Y%m%d-%H%M%S") + ("-" + args.style))
os.makedirs(run)
max_s = 60 + len(phases) * 300  # a saturated phase can take minutes; floods also stop via their ctl file


def now():
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC)


def write(path, text):
    with open(path + ".tmp", "w") as f:
        f.write(text)
    os.replace(path + ".tmp", path)


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def command_file(name, cmd):
    path = os.path.join(run, name + ".command")
    with open(path, "w") as f:
        f.write("#!/bin/bash\n" + cmd + "\nexit 0\n")
    os.chmod(path, 0o755)
    return path


if args.pid:
    iterm_pid = args.pid
else:
    candidates = subprocess.run(["pgrep", "-x", "iTerm2"], capture_output=True, text=True).stdout.split()
    if len(candidates) != 1:
        raise SystemExit(f"Found {len(candidates)} iTerm2 processes; pass --pid")
    iterm_pid = int(candidates[0])
log = open(os.path.join(run, "run.log"), "a", buffering=1)


def say(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    log.write(line + "\n")


say(f"iTerm2 pid={iterm_pid} phases={phases} rate={args.rate}KB/s fps={args.fps} style={args.style}")
ctls = []
for i in range(nflood):
    ctl = os.path.join(run, f"flood{i}.ctl")
    write(ctl, "wait")
    ctls.append(ctl)
    subprocess.run(["open", "-a", args.app, command_file(f"flood{i}", f"python3 '{TOOLS}/flood.py' '{ctl}' {args.rate} {args.fps} {max_s} {args.style}")], check=True)
    time.sleep(1.0)
subprocess.run(["open", "-a", args.app, command_file("probe", f"python3 '{TOOLS}/probe.py' '{run}' {max_s}")], check=True)

# Focus is reported only when it changes, so make sure the app becomes active after the probe starts.
time.sleep(3)
subprocess.run(["open", "-a", args.app], check=True)

focus = os.path.join(run, "probe-focus")
keys_log = os.path.join(run, "probe-keys.log")
t_end = time.monotonic() + 20
while read(focus) != "in" and time.monotonic() < t_end:
    time.sleep(0.1)
say(f"probe focus={read(focus)!r}")

results = []
try:
    for k in phases:
        for i, ctl in enumerate(ctls):
            write(ctl, "go" if i < k else "wait")
        time.sleep(3)
        # Sample while the keys are being injected, so the profile shows the loaded state.
        sampler = None
        if args.sample > 0:
            sampler = subprocess.Popen(["/usr/bin/sample", str(iterm_pid), str(int(args.sample)), "-file",
                                        os.path.join(run, f"sample-phase{k}.txt")],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cpu0 = cpu_seconds(iterm_pid)
        w0 = time.monotonic()
        phase_start = time.time()
        lat = []
        threads = []
        timeouts = 0
        skipped_focus = 0
        dsr_from = now()
        for _ in range(args.keys):
            if not args.ignore_focus and read(focus) != "in":
                skipped_focus += 1
                time.sleep(0.5)
                continue
            try:
                n_before = sum(1 for _ in open(keys_log))
            except OSError:
                n_before = 0
            t_send = now()
            for down in (True, False):
                post_key(iterm_pid, SPACE_KEYCODE, down)
            deadline = time.monotonic() + 2.0
            t_recv = None
            while time.monotonic() < deadline:
                try:
                    lines = open(keys_log).read().split()
                except OSError:
                    lines = []
                if len(lines) > n_before:
                    t_recv = int(lines[n_before])
                    break
                time.sleep(0.001)
            threads.append(thread_count(iterm_pid))
            if t_recv is None:
                timeouts += 1
            else:
                lat.append((t_recv - t_send) / 1e6)
            time.sleep(args.gap)
        cpu1 = cpu_seconds(iterm_pid)
        wall = time.monotonic() - w0
        phase_end = time.time()
        cpu = (cpu1 - cpu0) / wall * 100
        dsr = []
        try:
            for line in open(os.path.join(run, "probe-dsr.log")):
                sent, _, ms = line.split()
                if int(sent) >= dsr_from:
                    dsr.append(float(ms))
        except OSError:
            pass
        if sampler is not None:
            sampler.wait()

        def q(v, p):
            return statistics.quantiles(v, n=100, method="inclusive")[p - 1] if len(v) >= 2 else (v[0] if v else float("nan"))

        row = dict(floods=k, keys=len(lat), timeouts=timeouts, focus_skips=skipped_focus, cpu=cpu,
                   key_p50=q(lat, 50), key_p95=q(lat, 95), key_max=max(lat) if lat else float("nan"),
                   dsr_n=len(dsr), dsr_p50=q(dsr, 50), dsr_p95=q(dsr, 95), dsr_max=max(dsr) if dsr else float("nan"),
                   threads_max=max(threads) if threads else 0, rss_mb=rss_mb(iterm_pid))
        if args.exec_stats:
            wait_for_exec_stats(args.exec_stats, phase_end)
            row.update(exec_stats(args.exec_stats, phase_start, phase_end))
        results.append(row)
        with open(os.path.join(run, f"keys-phase{k}.txt"), "w") as f:
            f.write("\n".join(f"{x:.3f}" for x in lat) + "\n")
        say("floods={floods} iTermCPU={cpu:.0f}% key ms p50={key_p50:.1f} p95={key_p95:.1f} max={key_max:.1f} "
            "(n={keys}, timeouts={timeouts}, focus_skips={focus_skips}) | DSR ms p50={dsr_p50:.1f} p95={dsr_p95:.1f} "
            "max={dsr_max:.1f} (n={dsr_n}) | threads max={threads_max} RSS={rss_mb:.0f}MB".format(**row))
        if args.exec_stats:
            say("  join wait ms p50={join_p50:.2f} p95={join_p95:.2f} max={join_max:.2f} | overhead={overhead_frac:.4f} "
                "permit waits={waits} slice yields={yields}".format(**row))
finally:
    for ctl in ctls:
        write(ctl, "stop")
    write(os.path.join(run, "probe-stop"), "")
    with open(os.path.join(run, "results.tsv"), "w") as f:
        if results:
            f.write("\t".join(results[0]) + "\n")
            for r in results:
                f.write("\t".join(f"{v:.2f}" if isinstance(v, float) else str(v) for v in r.values()) + "\n")
    say("DONE " + run)
