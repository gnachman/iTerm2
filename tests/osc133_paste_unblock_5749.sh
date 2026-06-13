#!/usr/bin/env bash
#
# osc133_paste_unblock_5749.sh — Regression test for issue 5749.
#
# Before the OSC 133 k= work, Advanced Paste's "Wait for shell prompt"
# option would hang forever if the shell only emitted PS2 secondary
# prompts (e.g., the user pasted a multi-line script that triggered
# continuation prompts). The non-initial prompt was indistinguishable
# from "no prompt yet" so the paste sat in advanced-paste limbo.
#
# After the fix: VT100ScreenMutableState.terminalPromptDidStart routes
# non-initial kinds (k=s / k=c / k=r / k=unknown) to
# screenPromptOfNonInitialKindDidStart, which calls
# [iTermPasteHelper unblock] — letting Advanced Paste proceed even
# though no fresh primary prompt has fired.
#
# MANUAL TEST STEPS (the script is interactive; it walks you through):
#   1. Put any multi-line text on the clipboard. Easiest:
#        printf "foo\nbar\nbaz\n" | pbcopy
#   2. Run this script. It emits a primary prompt and pauses.
#   3. While paused: Edit → Paste Special → Advanced Paste...,
#      enable "Wait for shell prompt", click Paste.
#   4. Press Enter to continue. The script then emits PS2 prompts
#      slowly — Advanced Paste should advance past each instead of
#      hanging.
#
# Pacing knobs (override via env): PASTE_PAUSE (sec before PS2 burst,
# default 15) and PS2_DELAY (sec between PS2 prompts, default 3).
#
# Run from inside iTerm2: `bash tests/osc133_paste_unblock_5749.sh`

set -u

OSC="\033]"
ST="\033\\"

PASTE_PAUSE="${PASTE_PAUSE:-15}"
PS2_DELAY="${PS2_DELAY:-3}"

# Initial primary prompt + start of a here-doc command.
printf "${OSC}133;A${ST}"
printf "$ "
printf "${OSC}133;B${ST}"
printf "cat <<EOF\\\\\n"

# Pause before the PS2 burst so the user can set up Advanced Paste.
cat <<INSTRUCTIONS

================================================================
ISSUE 5749 PASTE-UNBLOCK TEST — paused before PS2 prompts.

  1. Edit → Paste Special → Advanced Paste...
  2. Enable "Wait for shell prompt".
  3. Click Paste.
  4. Press Enter here when ready.

The script will then emit 4 PS2 prompts, ${PS2_DELAY}s apart.
With the fix, Advanced Paste advances past each. Without the
fix, it sits idle waiting for a primary prompt.

(Override timing with PASTE_PAUSE and PS2_DELAY env vars.)
================================================================

INSTRUCTIONS

# Wait for the user to press Enter, with a hard cap so we don't hang
# forever if they didn't notice the prompt.
read -t "${PASTE_PAUSE}" -r -p "Press Enter when Advanced Paste is armed... " || true
printf "\n"

# Four secondary prompts in a row. No primary prompt between them.
# Advanced Paste with "Wait for shell prompt" must unblock on each.
i=1
for line in "first" "second" "third" "fourth"; do
    printf "${OSC}133;A;k=s${ST}"
    printf "> "
    printf "[ps2 %d/4 — waiting %ds] " "$i" "$PS2_DELAY"
    sleep "$PS2_DELAY"
    printf "${OSC}133;B${ST}"
    printf "%s\n" "$line"
    i=$((i + 1))
done

# Final terminator and command end.
printf "${OSC}133;A;k=s${ST}"
printf "> "
printf "${OSC}133;B${ST}"
printf "EOF\n"
printf "${OSC}133;C${ST}"
printf "first\nsecond\nthird\nfourth\n"
printf "${OSC}133;D;0${ST}"

cat <<DONE

Done. Verdict:
  * If Advanced Paste advanced past each '> ' prompt and delivered
    its clipboard payload during the burst above, the fix works.
  * If it sat there with the spinner / Cancel button visible until
    you hit Cancel, the unblock didn't fire — that's the 5749 bug.
DONE
