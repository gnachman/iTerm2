#!/bin/bash
# Repro for issue 13013: mouse-mode side-effect flood with herdr.
#
# Run this from INSIDE a herdr session (so `herdr pane ...` targets it), which
# itself must be running inside the iTerm2 build under test.
#
# It creates 3 panes each running a mouse-enabled TUI (vim), then rapidly
# focus-switches between them. Every focus move makes herdr re-assert mouse
# capture on the host terminal (the 12-sequence DECSET/DECRST burst). Each
# burst walks NONE -> 1000 -> 1002 -> 1003, which the 43bd1e07 same-mode guard
# cannot collapse, so it enqueues ~4 heavyweight screenMouseModeDidChange side
# effects per burst per pane. With shell-integration marks on the screen each
# side effect is more expensive. Type while this loops: input arrives in bursts.
#
# Usage:  ./herdr-13013-repro.sh [iterations]

set -euo pipefail
iterations="${1:-2000}"

if ! command -v herdr >/dev/null; then echo "herdr not found on PATH"; exit 1; fi
if [ -z "${HERDR_PANE:-}${HERDR_SESSION:-}" ]; then
  echo "Run this from inside a herdr session." >&2
fi

# Two vertical splits -> three panes side by side.
herdr pane split --current --direction right >/dev/null
herdr pane split --current --direction right >/dev/null

# Put a mouse-enabling TUI in each pane. vim enables 1000/1002/1006 with
# 'set mouse=a', so switching panes forces herdr to re-assert modes.
for p in $(herdr pane list | awk 'NR>1 {print $1}'); do
  herdr pane run "$p" bash -lc "printf 'set mouse=a\n' >/tmp/.herdr_vimrc; vim -u /tmp/.herdr_vimrc" >/dev/null 2>&1 || true
done

echo "Spamming $iterations focus switches. Type in iTerm2 to feel the lag. Ctrl-C to stop."
for ((i=0; i<iterations; i++)); do
  herdr pane focus --direction right >/dev/null 2>&1 || true
  herdr pane focus --direction left  >/dev/null 2>&1 || true
done
echo "done"
