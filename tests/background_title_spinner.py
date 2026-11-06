#!/usr/bin/env python3
# Animates the window title ten times a second for a minute. Run it in one
# tab, then select another tab in the same window. The first tab's title
# should keep spinning, not advance about once a second.
import sys
import time

frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
for i in range(600):
    sys.stdout.write(f"\033]0;{frames[i % len(frames)]} Probe {i:04d}\033\\")
    sys.stdout.flush()
    time.sleep(0.1)
