#!/usr/bin/env bash
#
# osc133_right_prompt.sh — Right-prompt (k=r) on the primary row.
#
# Simulates a shell that draws a left prompt ("$ "), then before the
# user starts typing, draws a clock at column 60 bracketed by A(k=r)/B.
# Then the user types a command and the cycle completes.
#
# Expected mark state: ONE prompt mark, with ONE excluded subrange
# covering columns ~60..72 on the prompt row ("[12:34:56]" is 10 chars
# but we tag the wrapping spaces too for visual clarity).
#
# WHAT TO CHECK:
#   1. ONE prompt mark on the prompt row, not two. Right-prompts must
#      not create a separate mark.
#   2. lastPromptLine, currentPromptRange, and lastCommandOutputRange
#      should reflect ONLY the primary prompt. (No public UI again —
#      check via `it2 session ...` or attach a debugger.)
#   3. Command "uptime" runs and its output appears below.
#   4. No fresh CR/LF gets inserted before the right-prompt — it must
#      stay on the same row as the "$ " primary prompt.
#
# Run from inside iTerm2: `bash tests/osc133_right_prompt.sh`

set -u

OSC="\033]"
ST="\033\\"

# Primary prompt at column 0
printf "${OSC}133;A${ST}"
printf "$ "

# Right-prompt: shell pads cursor over to col 60, then emits A(k=r)/B
# around the rendered clock text.
printf "%*s" 58 ""              # 58 spaces of padding (2 for "$ " + 58 = col 60)
printf "${OSC}133;A;k=r${ST}"
printf "[12:34:56]"             # 10 chars of right-prompt
printf "${OSC}133;B${ST}"

# Move cursor back to right after "$ " — real shells do this with CSI
# cursor-position. Easiest portable way: a CR + the prefix.
printf "\r"
printf "$ "

# Now the primary B fires and the user "types" their command.
printf "${OSC}133;B${ST}"
printf "uptime\n"
printf "${OSC}133;C${ST}"
printf " up 1 day,  3:14,  1 user,  load average: 0.42, 0.31, 0.28\n"
printf "${OSC}133;D;0${ST}"

printf "\nRight-prompt cycle complete. Verify: one prompt mark, one excluded subrange for '[12:34:56]'.\n"
