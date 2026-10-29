"""Helpers shared by the issue 13141 scripts: process measurements, and parsing the token execution
stats iTerm2 writes once a second when the hidden default NoSyncTokenExecutionStatsFile names a file.
"""
import re
import statistics
import subprocess
import time


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


def wait_for_exec_stats(path, end, warn, timeout=10):
    """Waits until iTerm2 has written the block covering time end. It writes one a second. Calls
    warn with a message if none appears within timeout seconds."""
    deadline = time.time() + timeout
    while not any(block_end(block) >= end for block in complete_blocks(path)):
        if time.time() > deadline:
            warn(f"warning: no token execution stats cover the end of the phase in {path}")
            return
        time.sleep(0.1)


NUMBER = r"([0-9.]+)"
PERCENTILES = r"p50=" + NUMBER + r"ms p95=" + NUMBER + r"ms max=" + NUMBER + r"ms n=(\d+)"


def _percentiles(text, label):
    """Combines a histogram line ("LABEL: p50=..ms p95=..ms max=..ms n=N") across blocks: the
    median of the medians, the worst p95 and max, and the total count."""
    p50, p95, worst, n = [], [], 0.0, 0
    for m in re.finditer(re.escape(label) + ": " + PERCENTILES, text):
        p50.append(float(m.group(1)))
        p95.append(float(m.group(2)))
        worst = max(worst, float(m.group(3)))
        n += int(m.group(4))
    if not p50:
        return dict(p50=float("nan"), p95=float("nan"), max=float("nan"), n=0)
    return dict(p50=statistics.median(p50), p95=max(p95), max=worst, n=n)


def exec_stats(path, start, end):
    """Summarizes the token execution stats iTerm2 wrote once a second between start and end (Unix
    times).

    Each block starts with "start=S end=E", the interval it covers. A block counts if it began in
    the interval, so the one covering the time before it is left out and the one written just after
    it ends is kept."""
    kept = []
    for block in complete_blocks(path):
        try:
            block_start = float(block.split(" ", 1)[0])
        except ValueError:
            continue
        if start <= block_start < end:
            kept.append(block)
    text = "\n".join(kept)
    overhead = busy = tokens_ms = 0.0
    waits = yields = 0
    mbps = []
    for m in re.finditer(r"permits " + NUMBER + r"ms, other " + NUMBER + r"ms, tokens " + NUMBER + r"ms, high-pri " + NUMBER + "ms", text):
        permits, other, tokens, high = (float(x) for x in m.groups())
        overhead += permits + other
        busy += permits + other + tokens + high
        tokens_ms += tokens
    for m in re.finditer(r"Waits for a permit: (\d+), slice yields: (\d+)", text):
        waits += int(m.group(1))
        yields += int(m.group(2))
    for m in re.finditer(r"Bytes executed: " + NUMBER + " MB/s", text):
        mbps.append(float(m.group(1)))
    join = _percentiles(text, "Join wait")
    key_to_executed = _percentiles(text, "Echo key to executed")
    executed_to_main = _percentiles(text, "Echo executed to main")
    handling = _percentiles(text, "Echo handling on main")
    return dict(overhead_frac=overhead / busy if busy else float("nan"),
                mbps=statistics.mean(mbps) if mbps else float("nan"),
                tokens_cpu=tokens_ms / 1000 / len(kept) if kept else float("nan"),
                waits=waits, yields=yields,
                join_p50=join["p50"], join_p95=join["p95"], join_max=join["max"],
                echo_n=executed_to_main["n"],
                echo_exec_p50=key_to_executed["p50"], echo_exec_p95=key_to_executed["p95"],
                echo_main_p50=executed_to_main["p50"], echo_main_p95=executed_to_main["p95"],
                echo_main_max=executed_to_main["max"],
                echo_handle_p50=handling["p50"], echo_handle_p95=handling["p95"])
