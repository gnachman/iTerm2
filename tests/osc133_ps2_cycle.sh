#!/usr/bin/env bash
#
# osc133_ps2_cycle.sh — Exercises a full PS2 (secondary-prompt) flow.
#
# Drives one logical command across three lines:
#   line 0:  $ echo \           ← primary prompt A→B, user types "echo \", newline
#   line 1:  > hi \             ← PS2 prompt A(k=s)→B, user types "hi \", newline
#   line 2:  > there            ← PS2 prompt A(k=s)→B, user types "there"
#   line 3:  hi there           ← C → output → D;0
#
# After this runs, the prompt mark on line 0 should carry TWO
# excludedSubranges covering the "> " prefix on lines 1 and 2.
#
# WHAT TO CHECK (after running):
#   1. Exactly ONE prompt mark on line 0 (not three) — open Marks menu
#      or scroll back; the "promptline" marker should appear once.
#   2. The mark's commandRange covers from after "$ " on line 0 through
#      "there" on line 2. (No public UI for this — Debug → Show Mark Info
#      if available, or just verify via a serialization round-trip.)
#   3. If you select all visible text + Edit > Copy with Styles, the PS2
#      "> " prefixes should be present in the copy (excluded-subrange
#      consumers are a future PR). Selection itself is just visual.
#   4. No tab-completion or partial-command weirdness — the shell
#      integration shouldn't think we're typing into a fresh command.
#
# Run from inside iTerm2: `bash tests/osc133_ps2_cycle.sh`

set -u

OSC="\033]"
ST="\033\\"

# Primary prompt on line 0
printf "${OSC}133;A${ST}"
printf "$ "
printf "${OSC}133;B${ST}"
printf "echo \\\\\n"

# Secondary prompt (PS2) on line 1
printf "${OSC}133;A;k=s${ST}"
printf "> "
printf "${OSC}133;B${ST}"
printf "hi \\\\\n"

# Secondary prompt (PS2) on line 2
printf "${OSC}133;A;k=s${ST}"
printf "> "
printf "${OSC}133;B${ST}"
printf "there\n"

# Command end → output → output end (exit 0)
printf "${OSC}133;C${ST}"
printf "hi there\n"
printf "${OSC}133;D;0${ST}"

printf "\nPS2 cycle complete. Verify: one prompt mark on the '\$ echo \\\\' line, two PS2 prefixes recorded as excluded subranges.\n"
