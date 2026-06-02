#!/bin/bash
# tests/osc133_mark_suppression.sh
#
# Manual UI verification of non-initial OSC 133 A mark-suppression (PR 2).
#
# Run from a shell with NO shell integration sourced. Watch the gutter
# (left margin) for mark icons. Press Return between tests.
#
# Layout per test (best-effort approximation of a real PS2 flow):
#
#   [PRIMARY]   <- OSC A here; expect ONE mark in the gutter
#   [SECONDARY] <- OSC A;k=... here; expect NO mark in the gutter
#     command   <- "user-typed" command continuation
#   output...   <- between OSC C and OSC D
#
# After each test:
#   - Cmd-Shift-Up should jump to the PRIMARY line.
#   - Edit > Copy Output of Last Command should capture the output lines.
#   - View > Inspector lets you read mark.kind and mark.promptDetectedByTrigger.

set -u

ESC=$'\e'
BEL=$'\a'

osc()    { printf '%s]133;%s%s' "$ESC" "$1" "$BEL"; }
say()    { printf '%s\n' "$1"; }
banner() { printf '\n========== %s ==========\n' "$1"; }

press() {
    printf '\n  >>> %s\n  >>> Press Return for next test... ' "$1"
    read -r _
    printf '\n'
}

# Drive a full PRIMARY + non-initial + output cycle, modeled after a real
# zsh/bash flow with PS1 + PS2: prompt and typed command share the same row,
# with B firing mid-line right after the prompt cells.
#
# Resulting layout (and debug-overlay expectations if the prompt-mark debug
# overlay is enabled via debugShowPromptMarkRangesInLegacyRenderer):
#   Row 0:  [LABEL PRIMARY] echo line1     blue prompt then green command
#   Row 1:  [LABEL SECONDARY k=...] echo line2
#                                          green command across the row, with
#                                          a red excluded-subrange overlay on
#                                          the SECONDARY prefix cells
#   Row 2:  line1                          output (no overlay)
#   Row 3:  line2                          output (no overlay)
#
#   $1 = test label (e.g. "3.1")
#   $2 = non-initial args (e.g. "k=s", "k=c", "k=r")
run_secondary_cycle() {
    local label="$1"
    local kind="$2"

    # Primary prompt: A, prompt cells, B, then typed command + newline.
    osc "A"
    printf '[%s PRIMARY] ' "$label"
    osc "B"
    printf 'echo line1\n'

    # Secondary prompt: A;k=..., prompt cells, B, then continuation command + newline.
    osc "A;$kind"
    printf '[%s SECONDARY %s] ' "$label" "$kind"
    osc "B"
    printf 'echo line2\n'

    # Output region, framed by C/D.
    osc "C"
    say "line1"
    say "line2"
    osc "D;0"
    printf '\n'
}

banner "OSC 133 mark suppression smoke tests"
say "Outer shell should have NO shell integration sourced."
say "Watch the gutter (left of each line) for mark icons."
press "Ready?"

# 3.1
banner "TEST 3.1  PRIMARY then A;k=s  (PS2-style; expect ONE mark)"
run_secondary_cycle "3.1" "k=s"
press "Verify:
        - ONE mark in the gutter on the [3.1 PRIMARY] row.
        - NO mark on the [3.1 SECONDARY k=s] row or output rows.
        - Cmd-Shift-Up lands on the [3.1 PRIMARY] row.
        - Edit > Copy Output of Last Command yields 'line1\\nline2'.
        - With debugShowPromptMarkRangesInLegacyRenderer enabled:
            blue   = '[3.1 PRIMARY] '   (prompt cells, A..B)
            green  = 'echo line1' on row 0 plus all of row 1 (command range)
            red    = '[3.1 SECONDARY k=s] '  on row 1 (excluded subrange)
            output rows have no overlay."

# 3.2a
banner "TEST 3.2a  PRIMARY then A;k=c  (continuation; expect ONE mark)"
run_secondary_cycle "3.2a" "k=c"
press "Verify: ONE mark on [3.2a PRIMARY]; SECONDARY clean."

# 3.2b
banner "TEST 3.2b  PRIMARY then A;k=r  (right-prompt; expect ONE mark)"
run_secondary_cycle "3.2b" "k=r"
press "Verify: ONE mark on [3.2b PRIMARY]; SECONDARY clean."

# 3.3 - trigger-detected primary survives A;k=s
banner "TEST 3.3  Trigger-detected primary preserved across A;k=s"
say "One-time setup before pressing Return:"
say "  Preferences > Profiles > [current] > Advanced > Triggers > Edit"
say "  Add a trigger:"
say "      Regex:  ^TRIGGERED_PRIMARY> "
say "      Action: Prompt Detected"
say "  Save the trigger and close Preferences."
press "Once the trigger is configured, press Return to run."

# The line below matches the trigger regex; the trigger creates a primary
# mark with promptDetectedByTrigger=YES. No OSC A is emitted for it. The
# subsequent OSC B closes the primary's prompt area like a normal flow.
say "TRIGGERED_PRIMARY> echo trig-line1"
osc "B"
osc "A;k=s"
say "[3.3 SECONDARY k=s after trigger-detected primary]"
osc "B"
say "  echo trig-line2"
osc "C"
say "trig-line1"
say "trig-line2"
osc "D;0"
press "Verify:
        - ONE mark on the TRIGGERED_PRIMARY line.
        - NO mark on [3.3 SECONDARY ...] or output rows.
        - Inspector on the primary mark still shows
          'Detected by trigger: YES' (or your build's equivalent label).
          A;k=s must NOT have flipped it back to NO."

banner "All mark-suppression smoke tests done."
