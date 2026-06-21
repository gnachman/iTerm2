#!/bin/bash
# Manual repro for the AsyncFilter "content delivered mid-search gets dropped" bug.
#
# Usage: tests/filter_midsearch_repro.sh [backlog_lines] [setup_delay_seconds]
#   backlog_lines        how many filler lines to print first (default 300000)
#   setup_delay_seconds  pause after the backlog so you can open the filter
#                        (default 15)
#
# Steps:
#   1. Run this in an iTerm2 session whose profile has a large/unlimited
#      scrollback.
#   2. It prints a big backlog of lines containing "needle", then pauses.
#   3. During the pause, open the filter (Edit > Find > Filter, Shift-Cmd-F)
#      and type:  needle
#      With a large backlog each filter pass takes longer than the 10ms
#      time slice, so the filter is frequently mid-search.
#   4. After the pause it emits five "LIVE needle N" lines slowly and then a
#      final "SENTINEL needle" line. These arrive while the filter is
#      mid-search.
#   5. Confirm the filtered view shows all five LIVE lines AND the SENTINEL.
#      Pre-fix, a line delivered during a mid-search pass can be missing
#      until you nudge the filter (type another character) or more output
#      arrives. Post-fix, they all appear.

set -u

BACKLOG="${1:-300000}"
DELAY="${2:-15}"
NEEDLE="needle"

printf 'Printing %s backlog lines containing "%s"...\n' "$BACKLOG" "$NEEDLE"
for ((i = 1; i <= BACKLOG; i++)); do
    echo "filler $i $NEEDLE"
done

printf '\n'
printf '==================================================================\n'
printf 'Backlog done. NOW open the filter: Edit > Find > Filter (Shift-Cmd-F)\n'
printf 'and type:  %s\n' "$NEEDLE"
printf 'Emitting LIVE matches in %s seconds...\n' "$DELAY"
printf '==================================================================\n'

for ((t = DELAY; t > 0; t--)); do
    printf '\r  %2ds remaining...' "$t"
    sleep 1
done
printf '\r                       \n'

for i in 1 2 3 4 5; do
    echo "LIVE $NEEDLE $i"
    sleep 0.15
done
echo "SENTINEL $NEEDLE"

printf '\nExpect the filtered view to show:\n'
printf '  LIVE %s 1 .. LIVE %s 5  and  SENTINEL %s\n' "$NEEDLE" "$NEEDLE" "$NEEDLE"
printf 'If any are missing (especially the last ones), that is the bug.\n'
