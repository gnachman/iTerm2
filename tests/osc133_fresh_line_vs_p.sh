#!/usr/bin/env bash
#
# osc133_fresh_line_vs_p.sh — Verify A/N force a fresh line; P does not.
#
# Per the spec and our parser:
#   * `OSC 133;A` and `OSC 133;N` may insert a CR+LF if the cursor isn't
#     at column 0 (gated by the shouldPlacePromptAtFirstColumn user pref).
#   * `OSC 133;P` is "prompt-start without fresh-line" — never forces
#     CR+LF regardless of the pref. Intended for sequences that follow
#     an earlier A/N (e.g. shell that draws the prompt in pieces).
#
# This script positions the cursor mid-line, then alternately fires A and
# P. With the pref enabled, A should bump us to col 0; P should not.
#
# WHAT TO CHECK:
#   * After "MID:" the next line should start "MID:$ ..." if P kept the
#     same line (correct) or "MID:" newline "$ ..." if P forced fresh
#     (incorrect — bug).
#   * After "MID2:" the next line should start on a NEW row "$ ..." if A
#     forced fresh (correct under default pref) or stay on the same row
#     (correct under "don't force fresh-line" pref).
#
# Run from inside iTerm2: `bash tests/osc133_fresh_line_vs_p.sh`

set -u

OSC="\033]"
ST="\033\\"

printf "MID:"
printf "${OSC}133;P${ST}"
printf "$ "
printf "${OSC}133;B${ST}"
printf "echo from-P\n"
printf "${OSC}133;C${ST}"
printf "from-P\n"
printf "${OSC}133;D;0${ST}"

printf "MID2:"
printf "${OSC}133;A${ST}"
printf "$ "
printf "${OSC}133;B${ST}"
printf "echo from-A\n"
printf "${OSC}133;C${ST}"
printf "from-A\n"
printf "${OSC}133;D;0${ST}"

printf "\nDone. Inspect the rows above:\n"
printf "  * 'MID:\$ echo from-P' SHOULD appear on a single row (P didn't force fresh-line).\n"
printf "  * 'MID2:' on one row and '\$ echo from-A' on the next (A forced fresh-line under the default pref).\n"
