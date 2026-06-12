#!/bin/bash
# Manual test for ToolStatus debouncing. Run in iTerm2 with the Session Status
# toolbelt visible (View > Toolbelt > Session Status).
#
# IMPORTANT: with only one session showing a status, the row has nowhere to
# move when its priority changes — you cannot see the bug. Open at least two
# extra tabs and run `decoy` in each so the toolbelt has multiple rows. Then
# run the actual test in another tab and watch its row.
#
# Recommended setup:
#   Tab 1: tests/test_status_debounce.sh decoy "Decoy A" working
#   Tab 2: tests/test_status_debounce.sh decoy "Decoy B" idle
#   Tab 3: tests/test_status_debounce.sh loop         # or any one-shot below
#
# All commands clear the status on Ctrl-C / exit.

set -u

WORKING_COLOR='#ff8e00'
IDLE_COLOR='#00da4b'
GREY='#888888'
TEST_COLOR='#ff00ff'   # distinctive magenta for the test row

osc() { printf '\e]21337;%s\a' "$1"; }
clear_status() { osc 'status=;indicator=;status-color='; }
working() { osc "status=${1:-Working};indicator=${WORKING_COLOR};status-color=${WORKING_COLOR}"; }
idle()    { osc "status=${1:-Idle};indicator=${IDLE_COLOR};status-color=${GREY}"; }

trap 'clear_status; printf "\n[cleared]\n"; exit 0' INT TERM

countdown() {
  for n in 3 2 1; do
    printf '\r  starting in %d...' "$n"
    sleep 1
  done
  printf '\r  GO              \n'
}

phase() { printf '\n  %s\n' "$*"; }

# ---------- Setup ----------

cmd_decoy() {
  local label="${1:-Decoy}" kind="${2:-working}"
  echo "Holding $kind status '$label' (Ctrl-C to clear)."
  case "$kind" in
    idle)        idle    "$label" ;;
    working|*)   working "$label" ;;
  esac
  while sleep 3600; do :; done
}

# ---------- Single-shot scenarios ----------
#
# Each prints:
#   START state
#   what burst will run
#   what to LOOK FOR
#   then waits for you to focus, counts down, fires the burst, holds the
#   end state long enough for you to confirm.

cmd_cancel_out() {
  echo "=== Cancel-out burst (the original bug) ==="
  phase 'Start state: Working (orange row labeled "Test")'
  working "Test"
  sleep 3
  phase 'About to fire: Idle -> Working back-to-back (sub-1ms apart).'
  phase 'WATCH FOR: row should NOT move to the Idle position and back.'
  phase 'If the debounce works, the row stays put. If broken, it slides.'
  countdown
  idle    "Test"
  working "Test"
  phase 'End state: Working. Hold for 5s.'
  sleep 5
  clear_status
}

cmd_remove_add() {
  echo "=== Remove + add ==="
  phase 'Start state: Working (one row labeled "Test")'
  working "Test"
  sleep 3
  phase 'About to fire: clear -> Working back-to-back.'
  phase 'WATCH FOR: still ONE row. No duplicate "Test" row.'
  countdown
  clear_status
  working "Test"
  phase 'End state: one Working row. Hold for 5s.'
  sleep 5
  clear_status
}

cmd_add_remove() {
  echo "=== Add + remove ==="
  phase 'Start state: no row for this tab.'
  clear_status
  sleep 3
  phase 'About to fire: Working -> clear back-to-back.'
  phase 'WATCH FOR: NO row appears at any point.'
  countdown
  working "Test"
  clear_status
  phase 'End state: still no row. Hold for 5s.'
  sleep 5
}

cmd_partial() {
  echo "=== Partial updates within one debounce window ==="
  phase 'Start state: no row.'
  clear_status
  sleep 3
  phase 'About to fire: indicator=magenta, then status="Combined" (no other fields).'
  phase 'WATCH FOR: row appears with BOTH a magenta dot AND the text "Combined".'
  phase 'If the indicator update is lost, you would see only text without the dot.'
  countdown
  osc "indicator=${TEST_COLOR}"
  osc 'status=Combined'
  phase 'End state: magenta dot + "Combined". Hold for 5s.'
  sleep 5
  clear_status
}

# ---------- Visual stress test ----------

cmd_loop() {
  echo 'Repeating cancel-out burst every 4 seconds. Ctrl-C to stop.'
  echo 'WATCH FOR: row stays on Working the whole time. Any blip = bug.'
  echo
  working "Test"
  while true; do
    sleep 4
    printf '  burst... '
    idle    "Test"
    working "Test"
    printf 'done\n'
  done
}

# ---------- Dispatch ----------

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Setup:
  decoy [LABEL] [working|idle]    Hold a status until Ctrl-C.
                                   Run in spare tabs so the toolbelt has
                                   multiple rows (otherwise motion is
                                   invisible).

Tests (run in a tab separate from the decoys):
  cancel-out      Working -> [Idle, Working] burst. Original bug repro.
  remove-add      Working -> [clear, Working] burst.
  add-remove      cleared -> [Working, clear] burst.
  partial         cleared -> [indicator-only, status-only] burst.
  loop            Repeat cancel-out forever (visual stress test).

EOF
}

cmd="${1:-}"
shift 2>/dev/null || true
case "$cmd" in
  decoy)       cmd_decoy "$@" ;;
  cancel-out)  cmd_cancel_out ;;
  remove-add)  cmd_remove_add ;;
  add-remove)  cmd_add_remove ;;
  partial)     cmd_partial ;;
  loop)        cmd_loop ;;
  ''|help|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
