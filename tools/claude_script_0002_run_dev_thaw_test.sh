#!/bin/bash
# Launch the freshly-built DEV iTerm2 directly (so env vars + stdout apply and we
# target the dev instance, NOT the side-by-side prod iTerm) and tail the
# freeze/thaw diagnostic log.
#
# Usage:
#   tools/claude_script_0002_run_dev_thaw_test.sh           # parking ON (the fix)
#   ITERM_WP_PARK=0 tools/claude_script_0002_run_dev_thaw_test.sh   # pre-fix failure mode
#
# Then in the dev window:
#   1. Open a terminal, run a UNIQUE command, e.g.:  /bin/sleep 4242
#   2. Window Projects: create a project, associate this window, "Freeze (Keep Jobs Running)".
#   3. Confirm the window closed and `pgrep -f "sleep 4242"` still shows it alive.
#   4. "Restore" the window from the project.
#   5. Read the log below. Success == childPresent=true AND reattached=true,
#      and the restored terminal is BLOCKED (no fresh prompt) until you kill the sleep.
set -u

DEV_BIN="/Users/ysaxon/Library/Developer/Xcode/DerivedData/iTerm2-hghphmhudlrmuogydilxgbnitkjo/Build/Products/Development/iTerm2.app/Contents/MacOS/iTerm2"
LOG="/tmp/iterm_wp.log"

: "${ITERM_WP_PARK:=1}"
export ITERM_WP_PARK

echo "ITERM_WP_PARK=$ITERM_WP_PARK"
echo "Truncating $LOG"
: > "$LOG"

if [ ! -x "$DEV_BIN" ]; then
  echo "Dev binary not found at $DEV_BIN — build first with tools/build.sh Development" >&2
  exit 1
fi

echo "Launching DEV iTerm2 (pid will be printed). Prod iTerm is untouched."
"$DEV_BIN" &
echo "dev pid: $!"

echo "----- tailing $LOG (Ctrl-C to stop) -----"
tail -f "$LOG"
