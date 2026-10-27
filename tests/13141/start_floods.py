#!/usr/bin/env python3
# Adapted from the reproducer attached to issue 13141 by its reporter.
"""Open N iTerm2 sessions that flood output (flood.py), keep them running, then stop them.

Each session is opened with `open -a iTerm <file>.command`, the same way run_experiment.py
opens them. Type in any other iTerm2 session while this runs.
Usage: start_floods.py [N=9] [KB_PER_SEC=2000] [SECONDS=120] [APP=iTerm]
"""
import os
import subprocess
import sys
import tempfile
import time

n = int(sys.argv[1]) if len(sys.argv) > 1 else 9
rate = float(sys.argv[2]) if len(sys.argv) > 2 else 2000
seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 120
app = sys.argv[4] if len(sys.argv) > 4 else "iTerm"

flood = os.path.join(os.path.dirname(os.path.abspath(__file__)), "flood.py")
work = tempfile.mkdtemp(prefix="iterm-flood-")
ctl = os.path.join(work, "ctl")
with open(ctl, "w") as f:
    f.write("go")

for i in range(n):
    cmd = os.path.join(work, f"flood{i}.command")
    with open(cmd, "w") as f:
        f.write(f"#!/bin/bash\nexec python3 '{flood}' '{ctl}' {rate} 20 {seconds + 30}\n")
    os.chmod(cmd, 0o755)
    subprocess.run(["open", "-a", app, cmd], check=True)
    time.sleep(0.5)

print(f"{n} sessions flooding at {rate:.0f} KB/s each for {seconds:.0f} s.")
print("Type in any other iTerm2 session now; then toggle Settings > General > Magic >")
print('"Maximize throughput at the cost of higher latency" (applies live) and type again.')
print("Ctrl-C stops the floods early.")
try:
    time.sleep(seconds)
except KeyboardInterrupt:
    pass
finally:
    with open(ctl, "w") as f:
        f.write("stop")
    print("Floods stopped.")
