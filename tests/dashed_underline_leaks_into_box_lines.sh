#!/bin/bash
# Repro for GitLab #12907: with "Use ligatures" ON, a dashed underline (SGR 4:5)
# on screen leaks its dash pattern into box-drawing lines (U+2500) drawn below it,
# so the box lines render dashed instead of solid.
#
# How to use:
#   1. Turn ON Settings > Advanced > (Drawing) "Use solid underlines?". This is
#      the required trigger: it routes underline drawing through a path that
#      strokes directly onto the shared window context, so a dashed underline's
#      dash pattern leaks into later strokes. With the default (masked) path the
#      draw is wrapped in save/restore and the leak does not occur.
#   2. On the active profile, pick a ligature font (Fira Code, JetBrains Mono, ...)
#      and turn on Settings > Profiles > Text > Use ligatures.
#   3. Run this script. Keep both blocks visible at once.
#   4. The box-drawing lines below the dashed underline should render dashed while
#      the underline is on screen. Scroll it off screen, or toggle "Use ligatures"
#      off, and the box lines revert to solid.

# A dashed underline (SGR 4:5), drawn on a row above the box lines.
printf '\033[4:5mThis line has a dashed underline\033[0m\n'

# Box-drawing horizontal lines. These should always be solid.
for _ in 1 2 3 4 5 6; do
  printf '%s\n' '──────────────────────────────────────────'
done

# A framed box, like a TUI input area, to mirror the report more closely.
printf '%s\n' '┌────────────────────────────────────────┐'
printf '%s\n' '│ input area                             │'
printf '%s\n' '└────────────────────────────────────────┘'
