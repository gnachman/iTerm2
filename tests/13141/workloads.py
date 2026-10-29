#!/usr/bin/env python3
"""Measure how fast iTerm2 processes output, and at what CPU cost, across a fixed set of workloads.

No single mix of line lengths and content is representative, so each workload aims at a different
cost. Comparing two builds on the same workload shows which costs moved.

    seq-direct  `seq` writing straight to the terminal: one write() per line, as build logs do.
                The kernel's tty layer is the ceiling here, not iTerm2.
    short       Short lines (seq output) in large writes: line feeds and scrolling dominate.
    long70      70-character lines: the ASCII append path, no wrapping in an 80-column window.
    long500     500-character lines: the same, wrapping.
    color       A color change every 4 characters: the parser and graphic renditions.
    unicode     CJK, emoji, and combining marks: the slow paths for wide and combining characters.
    fullscreen  Whole-screen redraws by cursor addressing, as full-screen apps do: no scrollback.

Every workload but seq-direct is `cat` of a file generated once into OUT_DIR/data, so the producer is
never the bottleneck and runs are repeatable. For each workload and session count, the sessions start
together, run for a warm-up, then for the measured window, then stop.

Usage:
    workloads.py OUT_DIR --stats FILE [--app PATH] [--pid PID] [--sessions 1,4,16]
                 [--workloads short,long70] [--seconds 10] [--warmup 3] [--size-mb 64]

--stats is the file iTerm2 writes token execution stats to; iTerm2 must be writing them there:
    defaults write com.googlecode.iterm2 NoSyncTokenExecutionStatsFile /tmp/exec-stats.txt
(in the defaults domain of the build under test). Keep the default profile's scrollback setting and
window size the same between runs you compare: both change the cost per line a lot.

Results: one line per workload and session count, also written to OUT_DIR/run-*/results.tsv:
executed MB/s (total), iTerm2's CPU (100% = one core), CPU-seconds per GB executed, CPU-seconds a
second spent executing tokens, the overhead fraction of execution, and waits for an execution permit.
"""
import argparse
import os
import random
import subprocess
import sys
import time

from harness import cpu_seconds, exec_stats, wait_for_exec_stats

WORKLOADS = ["seq-direct", "short", "long70", "long500", "color", "unicode", "fullscreen"]


def generate(name, path, size):
    """Writes about `size` bytes of the workload to path."""
    rng = random.Random(13141)
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
    wide = "漢字仮名交じり文表示速度試験中日本語中文한국어"
    emoji = "😀🎉🚀🌍🔥✨"
    combining = ["é", "ä", "ô", "ñ"]

    def line_of(length):
        return "".join(rng.choice(letters) for _ in range(length))

    chunks = []
    written = 0
    n = 1
    row = 0
    while written < size:
        if name == "short":
            text = "".join(f"{i}\n" for i in range(n, n + 10000))
            n += 10000
        elif name == "long70":
            text = "".join(line_of(70) + "\n" for _ in range(1000))
        elif name == "long500":
            text = "".join(line_of(500) + "\n" for _ in range(200))
        elif name == "color":
            lines = []
            for _ in range(1000):
                parts = []
                for _ in range(18):
                    parts.append(f"\x1b[3{rng.randrange(8)};4{rng.randrange(8)}m{line_of(4)}")
                lines.append("".join(parts) + "\x1b[m\n")
            text = "".join(lines)
        elif name == "unicode":
            lines = []
            for _ in range(1000):
                parts = []
                for _ in range(20):
                    kind = rng.randrange(3)
                    if kind == 0:
                        parts.append(rng.choice(wide))
                    elif kind == 1:
                        parts.append(rng.choice(emoji))
                    else:
                        parts.append(rng.choice(combining))
                lines.append("".join(parts) + "\n")
            text = "".join(lines)
        elif name == "fullscreen":
            frames = []
            for _ in range(20):
                rows = []
                for r in range(1, 25):
                    rows.append(f"\x1b[{r};1H{line_of(79)}")
                frames.append("\x1b[H" + "".join(rows))
                row += 1
            text = "".join(frames)
        else:
            raise SystemExit(f"Unknown workload {name}")
        data = text.encode("utf-8")
        chunks.append(data)
        written += len(data)
    with open(path + ".tmp", "wb") as f:
        for chunk in chunks:
            f.write(chunk)
    os.replace(path + ".tmp", path)


def session_script(workload, data_file, run, index):
    """The shell script one session runs: signal ready, wait for go, produce output until stop."""
    if workload == "seq-direct":
        produce = "seq 1 999999999"
    else:
        produce = f"while :; do cat '{data_file}'; done"
    return f"""#!/bin/bash
touch '{run}/ready-{index}'
while [ ! -f '{run}/go' ]; do sleep 0.05; done
( {produce} ) &
producer=$!
while [ ! -f '{run}/stop' ]; do sleep 0.1; done
pkill -P $producer
kill $producer 2>/dev/null
wait $producer 2>/dev/null
touch '{run}/done-{index}'
exit 0
"""


def wait_for_files(paths, timeout, what):
    deadline = time.time() + timeout
    while not all(os.path.exists(p) for p in paths):
        if time.time() > deadline:
            missing = sum(1 for p in paths if not os.path.exists(p))
            raise SystemExit(f"Timed out waiting for {what} ({missing} of {len(paths)} missing)")
        time.sleep(0.1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out_root")
    ap.add_argument("--stats", required=True, help="file iTerm2 writes token execution stats to")
    ap.add_argument("--app", default="iTerm", help="app to open sessions in, passed to open -a")
    ap.add_argument("--pid", type=int, default=0, help="iTerm2 process id (default: the only one named iTerm2)")
    ap.add_argument("--sessions", default="1,4,16", help="session counts to run each workload with")
    ap.add_argument("--workloads", default=",".join(WORKLOADS), help="comma-separated, from: " + ", ".join(WORKLOADS))
    ap.add_argument("--seconds", type=float, default=10, help="length of the measured window")
    ap.add_argument("--warmup", type=float, default=3, help="seconds of output before measuring")
    ap.add_argument("--size-mb", type=float, default=64, help="size of each generated data file")
    args = ap.parse_args()

    workloads = args.workloads.split(",")
    for w in workloads:
        if w not in WORKLOADS:
            raise SystemExit(f"Unknown workload {w}")
    counts = [int(x) for x in args.sessions.split(",")]

    if args.pid:
        pid = args.pid
    else:
        candidates = subprocess.run(["pgrep", "-x", "iTerm2"], capture_output=True, text=True).stdout.split()
        if len(candidates) != 1:
            raise SystemExit(f"Found {len(candidates)} iTerm2 processes; pass --pid")
        pid = int(candidates[0])

    root = os.path.abspath(args.out_root)
    data_dir = os.path.join(root, "data")
    os.makedirs(data_dir, exist_ok=True)
    out = os.path.join(root, time.strftime("run-%Y%m%d-%H%M%S"))
    os.makedirs(out)
    log = open(os.path.join(out, "run.log"), "a", buffering=1)

    def say(msg):
        line = time.strftime("%H:%M:%S ") + msg
        print(line, flush=True)
        log.write(line + "\n")

    size = int(args.size_mb * 1024 * 1024)
    for w in workloads:
        if w == "seq-direct":
            continue
        path = os.path.join(data_dir, f"{w}-{int(args.size_mb)}mb.txt")
        if not os.path.exists(path):
            say(f"generating {path}")
            generate(w, path, size)

    say(f"iTerm2 pid={pid} workloads={workloads} sessions={counts} seconds={args.seconds} warmup={args.warmup}")
    header = "workload\tsessions\tMB/s\tcpu%\tcpu_s_per_GB\ttokens_cpu_s_per_s\toverhead\tpermit_waits"
    results = [header]
    for w in workloads:
        data_file = os.path.join(data_dir, f"{w}-{int(args.size_mb)}mb.txt")
        for n in counts:
            run = os.path.join(out, f"{w}-{n}")
            os.makedirs(run)
            for i in range(n):
                script = os.path.join(run, f"session-{i}.command")
                with open(script, "w") as f:
                    f.write(session_script(w, data_file, run, i))
                os.chmod(script, 0o755)
                subprocess.run(["open", "-a", args.app, script], check=True)
            wait_for_files([os.path.join(run, f"ready-{i}") for i in range(n)], 60, "sessions to start")
            open(os.path.join(run, "go"), "w").close()
            time.sleep(args.warmup)
            start = time.time()
            cpu0 = cpu_seconds(pid)
            time.sleep(args.seconds)
            cpu1 = cpu_seconds(pid)
            end = time.time()
            open(os.path.join(run, "stop"), "w").close()
            wait_for_files([os.path.join(run, f"done-{i}") for i in range(n)], 60, "sessions to stop")
            wait_for_exec_stats(args.stats, end, say)
            stats = exec_stats(args.stats, start, end)
            cpu = (cpu1 - cpu0) / (end - start) * 100
            gb = stats["mbps"] * (end - start) / 1000
            cpu_per_gb = (cpu1 - cpu0) / gb if gb > 0 else float("nan")
            row = dict(workload=w, sessions=n, cpu=cpu, cpu_per_gb=cpu_per_gb, **stats)
            say("{workload:10} sessions={sessions:3} MB/s={mbps:7.1f} cpu={cpu:5.0f}% cpu_s/GB={cpu_per_gb:6.1f} "
                "tokens_cpu_s/s={tokens_cpu:5.2f} overhead={overhead_frac:.4f} permit_waits={waits}".format(**row))
            results.append(f"{w}\t{n}\t{stats['mbps']:.1f}\t{cpu:.0f}\t{cpu_per_gb:.1f}\t{stats['tokens_cpu']:.2f}\t"
                           f"{stats['overhead_frac']:.4f}\t{stats['waits']}")
            # Let the sessions' windows close and iTerm2 settle before the next run.
            time.sleep(2)
    with open(os.path.join(out, "results.tsv"), "w") as f:
        f.write("\n".join(results) + "\n")
    say(f"DONE {out}")


if __name__ == "__main__":
    sys.exit(main())
