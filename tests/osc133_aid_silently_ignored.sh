#!/usr/bin/env bash
#
# osc133_aid_silently_ignored.sh — `aid=` should be silently skipped.
#
# The N variant of OSC 133 is spec'd to also "implicitly terminate" the
# currently-active command by referring to its `aid=` (application id).
# Our parser doesn't implement implicit termination yet — the comment
# above `promptKindFromArgs:` says: "aid= is silently ignored by the
# args parser, so nothing gets lost."
#
# This script emits a mix of `aid=` and `k=` arguments to confirm:
#   1. Unknown keys don't crash the parser.
#   2. `k=` is still picked up regardless of `aid=` ordering.
#   3. The active command continues uninterrupted (since we don't yet
#      do the implicit-terminate).
#
# WHAT TO CHECK:
#   * No crash, no parse errors in the iTerm2 log.
#   * Each prompt-kind log line shows the right kind even though `aid=`
#     was sprinkled in.
#
# Run from inside iTerm2: `bash tests/osc133_aid_silently_ignored.sh`

set -u

OSC="\033]"
ST="\033\\"

cycle() {
    local label=$1 args=$2
    printf "${OSC}133;A${args}${ST}"
    printf "$ "
    printf "${OSC}133;B${ST}"
    printf "echo %s\n" "${label}"
    printf "${OSC}133;C${ST}"
    printf "%s\n" "${label}"
    printf "${OSC}133;D;0${ST}"
}

cycle "aid-before-k"   ";aid=abc;k=i"
cycle "aid-after-k"    ";k=s;aid=def"
cycle "aid-only"       ";aid=ghi"
cycle "k-and-junk"     ";aid=jkl;junk=mno;k=r;another=pqr"
cycle "N-with-aid"     ";aid=xyz;k=i"      # ← This one really should test N, see below

# N variant: same as A but the parser comment notes implicit-termination
# isn't wired up yet. Verify it acts like A.
printf "${OSC}133;N;aid=abc;k=s${ST}"
printf "> "
printf "${OSC}133;B${ST}"
printf "after-N\n"
printf "${OSC}133;C${ST}"
printf "after-N\n"
printf "${OSC}133;D;0${ST}"

printf "\nDone. Five A cycles + one N cycle with assorted aid= args. All should parse cleanly.\n"
