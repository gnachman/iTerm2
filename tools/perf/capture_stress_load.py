#!/usr/bin/env python3
"""Capture a fixed, repeatable slice of stress_load.py's output.

tools/perf/run_stress_test.sh drives a running iTerm2 with stress_load.py in
many tabs. ModernTests/StressStreamReplayTests.swift replays the same output
into a VT100Screen in the test host instead, so that the integer sanitizers
see the stress inputs without the app being launched
(docs/swift-migration/integer-findings.md). This script writes that output.

Usage:
    python3 -B tools/perf/capture_stress_load.py OUTPUT

It imports stress_load.py from this directory and runs every terminal output
stress mode (normal, buffer, clearcodes) and every dashboard mode (htop,
watch, progress, table, status), one after another, with:

- random seeded with 0 before each mode, so the dashboards' fake data is the
  same on every run;
- a fake clock that advances by STEP seconds each time it is read and a
  time.sleep that does nothing, so each mode runs a fixed number of
  iterations instead of for a number of real seconds;
- time.strftime given the epoch instead of the current time, for the watch
  dashboard's clock;
- a terminal of 80 columns and 24 rows (COLUMNS and LINES);
- "\\n" written as "\\r\\n", as a pty with onlcr (the default) delivers it.

flood (which runs `yes`) and the --title timer thread are left out: neither
is deterministic. The banner lines stress_load.py prints are kept, as the
terminal sees them in the harness.

The capture in the tree, tests/stress_load_capture.txt, was made with this
script; run it again after changing stress_load.py's patterns.
"""

import contextlib
import io
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

STEP = 0.001  # seconds per clock read
STRESS_SECONDS = 0.15  # 150 iterations per stress mode (one clock read per iteration)
DASHBOARD_SECONDS = 0.045  # about 15 frames per dashboard mode (three clock reads per frame)


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def time(self):
        self.now += STEP
        return self.now

    def sleep(self, seconds):
        pass


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    os.environ["COLUMNS"] = "80"
    os.environ["LINES"] = "24"
    import stress_load  # noqa: E402

    clock = FakeClock()
    stress_load.time.time = clock.time
    stress_load.time.sleep = clock.sleep
    real_strftime = time.strftime
    stress_load.time.strftime = lambda fmt, t=None: real_strftime(fmt, time.gmtime(0))
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        for mode in ("normal", "buffer", "clearcodes"):
            random.seed(0)
            stress_load.stress_test(STRESS_SECONDS, label="tab_1", modes=[mode])
        for mode in ("htop", "watch", "progress", "table", "status"):
            random.seed(0)
            stress_load.run_dashboard(DASHBOARD_SECONDS, label="tab_1", mode_name=mode, fps=30)
    data = out.getvalue().replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
    with open(argv[1], "wb") as f:
        f.write(data)
    sys.stderr.write("wrote %d bytes to %s\n" % (len(data), argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
