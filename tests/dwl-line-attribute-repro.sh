#!/bin/bash
#
# Repro for iTerm2 issue 13055: a DECDHL/DECDWL line attribute is never cleared
# by erasures or by scrolling a scroll region, so a host app that draws a
# double-height title and then repaints the screen gets a giant, clipped row
# where normal text belongs.
#
# Run this inside iTerm2, on the main (not alternate) screen:
#
#     tests/dwl-line-attribute-repro.sh            # automatic checks
#     tests/dwl-line-attribute-repro.sh --pause    # stop after each step so
#                                                  # you can look at the screen
#
# Each case scribbles on the screen and then wipes it, so without --pause you
# will see a flicker and then the report. The report is printed once, at the
# end, and is the thing to read.
#
# How the automatic probe works: on a double-width line CUP takes a *logical*
# column and iTerm2 maps it to a physical cell (logical 10 -> physical 18),
# while CPR (ESC[6n) reports the *physical* column. So parking the cursor at
# logical column 10 and asking where it is answers "is this row still
# double-width?": 10 means single-width, 19 means double-width.
#
# Where the expected results come from: DEC's VT510 Programmer Information
# defines ED as "This control function erases characters from part or all of the
# display. When you erase complete lines, they become single-height,
# single-width lines, with all visual character attributes cleared." The EL
# description says only that it clears character attributes, and says nothing
# about line attributes. xterm implements exactly that split (screen.c
# ClearBufRows resets SetLineDblCS with the comment "clearing the whole row
# resets the doublesize characters", called from ED 0/1/2; ClearInLine never
# touches it) and carries the attribute with the content when it scrolls.
#
# xterm promotes ED 0 from the home position, and ED 1 from the last cell, to
# ED 2, so those reset every row -- which is why case 1 below expects a reset on
# a row the cursor is nowhere near. The two sources diverge only when the cursor
# sits at column 1 of some *other* row: that row is erased completely, so DEC's
# wording calls for a reset, and xterm's ClearBelow does not do one. We follow
# xterm, which was the only implementation of these codes for long enough that
# apps are written against it rather than against the manual.

set -u

PAUSE=0
if [ "${1:-}" = "--pause" ]; then
    PAUSE=1
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "This script must be run interactively in a terminal." >&2
    exit 1
fi

TITLE_ROW=10      # row the double-height title goes on
PROBE_COL=10      # logical column the probe parks the cursor at
SINGLE=$PROBE_COL # CPR column reported when the row is single-width
DOUBLE=$(( (PROBE_COL - 1) * 2 + 1 ))  # ...and when it is double-width

failures=0
results=()        # the report, printed all at once at the end
saved_stty=$(stty -g)
raw=0

cleanup() {
    local r
    if [ "$raw" = 1 ]; then
        # Drop the double-width attribute from every row before leaving,
        # otherwise the shell prompt inherits a giant line.
        for (( r = 1; r <= rows; r++ )); do
            printf '\033[%d;1H\033#5' "$r" > /dev/tty
        done
        printf '\033[r' > /dev/tty
        stty "$saved_stty"
        raw=0
    fi
}

# Reads a CPR response and echoes "row col".
read_cpr() {
    local esc row col
    printf '\033[6n' > /dev/tty
    IFS='[;' read -r -d R -t 2 esc row col < /dev/tty || return 1
    printf '%s %s\n' "$row" "$col"
}

# Parks the cursor at logical column $PROBE_COL of row $1 and echoes the
# physical column the terminal reports.
probe_row() {
    local reply
    printf '\033[%d;%dH' "$1" "$PROBE_COL" > /dev/tty
    reply=$(read_cpr) || { echo "timeout"; return; }
    echo "${reply#* }"
}

# Puts every row back to single-width and clears the screen, so each case
# starts from a known state without relying on the behavior under test.
reset_screen() {
    local r
    for (( r = 1; r <= rows; r++ )); do
        printf '\033[%d;1H\033#5' "$r" > /dev/tty
    done
    printf '\033[r\033[2J\033[H' > /dev/tty
}

# Draws a DECDHL top/bottom pair at $TITLE_ROW with some body text under it.
draw_title_screen() {
    printf '\033[%d;1H\033#3      Chronicles' "$TITLE_ROW" > /dev/tty
    printf '\033[%d;1H\033#4      Chronicles' "$((TITLE_ROW + 1))" > /dev/tty
    printf '\033[%d;1HVersion May 2026' "$((TITLE_ROW + 3))" > /dev/tty
    printf '\033[%d;1HDatabase initials:' "$((TITLE_ROW + 5))" > /dev/tty
}

# Collect a line of the end-of-run report.
say() { results+=("$1"); }

# check <name> <expected-col> <actual-col> <explanation-if-it-fails>
check() {
    local name=$1 expected=$2 actual=$3 why=$4
    if [ "$actual" = "$expected" ]; then
        say "  $(printf '\033[32mPASS\033[m') $name"
    else
        say "  $(printf '\033[31mFAIL\033[m') $name"
        say "       expected CPR column $expected, got $actual"
        say "       $why"
        failures=$((failures + 1))
    fi
}

# With --pause, label what is on the screen (on the bottom row, out of the way
# of the title under test) and wait for a keypress. Enter arrives as CR in raw
# mode, so read one character rather than waiting for a newline.
step() {
    if [ "$PAUSE" = 1 ]; then
        printf '\033[%d;1H\033[2K%s -- press any key' "$rows" "$1" > /dev/tty
        read -r -n 1 _ < /dev/tty
    fi
}

stty raw -echo
raw=1
trap cleanup EXIT

# Find the screen size the terminal actually reports.
printf '\033[999;999H' > /dev/tty
size=$(read_cpr) || { cleanup; echo "Terminal did not answer ESC[6n." >&2; exit 1; }
rows=${size% *}
if [ "$rows" -lt $((TITLE_ROW + 8)) ]; then
    cleanup
    echo "Window is only $rows rows; please make it at least $((TITLE_ROW + 8))." >&2
    exit 1
fi

# Sanity check: does this terminal implement double-width lines at all, and does
# the probe see it? (3.6.11 and earlier ignore ESC #3/#4, and correctly so
# report every row as single-width.)
reset_screen
printf '\033[%d;1H\033#6double width' "$TITLE_ROW" > /dev/tty
baseline=$(probe_row "$TITLE_ROW")
if [ "$baseline" != "$DOUBLE" ]; then
    reset_screen
    cleanup
    echo "This terminal reports column $baseline for a DECDWL row, not $DOUBLE."
    echo "Either it does not implement DECDWL (pre-3.7.0 iTerm2) or the probe"
    echo "does not apply. Nothing to test."
    exit 0
fi

# ---------------------------------------------------------------------------
# Case 1: ED 0 (CSI H, CSI J) -- the shape the app in the issue uses.
# ---------------------------------------------------------------------------
reset_screen
draw_title_screen
step "case 1: double-height title drawn"
printf '\033[H\033[J' > /dev/tty                       # home, erase to end of display
printf '\033[%d;1HMain Menu' "$TITLE_ROW" > /dev/tty   # repaint, expecting normal text
after=$(probe_row "$TITLE_ROW")
step "case 1: erased with CSI H CSI J, then repainted"
say ""
say "Case 1: repaint after CSI H CSI J (erase display below cursor)"
check "ED 0 clears the attribute on fully-erased rows" "$SINGLE" "$after" \
      "row $TITLE_ROW is still double-width, so the repainted text is drawn giant"

# ---------------------------------------------------------------------------
# Case 2: ED 1 (CSI 1J) from the bottom of the screen.
# ---------------------------------------------------------------------------
reset_screen
draw_title_screen
printf '\033[%d;1H\033[1J' "$rows" > /dev/tty          # erase from start of display to cursor
printf '\033[%d;1HMain Menu' "$TITLE_ROW" > /dev/tty
after=$(probe_row "$TITLE_ROW")
step "case 2: erased with CSI 1J, then repainted"
say ""
say "Case 2: repaint after CSI 1J (erase display above cursor)"
check "ED 1 clears the attribute on fully-erased rows" "$SINGLE" "$after" \
      "row $TITLE_ROW is still double-width after being erased"

# ---------------------------------------------------------------------------
# Case 3: ED 2 (CSI 2J). iTerm2 happens to get this one right, because
# erase-whole-display scrolls the screen into history first and that recycles
# the per-line metadata. Included so a fix does not regress it.
# ---------------------------------------------------------------------------
reset_screen
draw_title_screen
printf '\033[2J' > /dev/tty
printf '\033[%d;1HMain Menu' "$TITLE_ROW" > /dev/tty
after=$(probe_row "$TITLE_ROW")
step "case 3: erased with CSI 2J, then repainted"
say ""
say "Case 3: repaint after CSI 2J (erase whole display)"
check "ED 2 clears the attribute" "$SINGLE" "$after" \
      "row $TITLE_ROW is still double-width after the screen was erased"

# ---------------------------------------------------------------------------
# Case 4: scrolling a scroll region. The characters move up a row but the line
# attribute stays behind, so the moved text loses its double width and the row
# it left keeps a stale one.
# ---------------------------------------------------------------------------
reset_screen
printf '\033[%d;1H\033#6Chronicles' "$TITLE_ROW" > /dev/tty
step "case 4: double-width text on row $TITLE_ROW"
printf '\033[%d;%dr' "$((TITLE_ROW - 2))" "$((TITLE_ROW + 5))" > /dev/tty  # DECSTBM
printf '\033[%d;1H\033D' "$((TITLE_ROW + 5))" > /dev/tty                   # IND at the bottom: scroll up 1
moved=$(probe_row "$((TITLE_ROW - 1))")   # where the text landed
vacated=$(probe_row "$TITLE_ROW")         # where it came from
printf '\033[r' > /dev/tty
step "case 4: scroll region scrolled up one row"
say ""
say "Case 4: scrolling a scroll region moves the text up one row"
check "the attribute follows the text to row $((TITLE_ROW - 1))" "$DOUBLE" "$moved" \
      "the text moved but the double-width attribute did not, so it draws at normal width with gaps"
check "the vacated row $TITLE_ROW is back to single-width" "$SINGLE" "$vacated" \
      "the row the text left still claims to be double-width"

# ---------------------------------------------------------------------------
# Case 5: entering the alternate screen. The alternate screen's grid outlives a
# trip through the primary buffer, so an attribute left behind on one visit is
# still there on the next. (RIS and Clear Buffer have the same defect but are
# not scripted here: RIS would reset colors, tab stops and more in the terminal
# you are running this in. The unit tests cover those two instead.)
# ---------------------------------------------------------------------------
reset_screen
printf '\033[?1049h' > /dev/tty
printf '\033[%d;1H\033#6Chronicles' "$TITLE_ROW" > /dev/tty
step "case 5: double-width text on the alternate screen"
printf '\033[?1049l' > /dev/tty        # back to the primary screen
printf '\033[?1049h' > /dev/tty        # and into the alternate screen again
after=$(probe_row "$TITLE_ROW")
printf '\033[?1049l' > /dev/tty
step "case 5: left and re-entered the alternate screen"
say ""
say "Case 5: re-entering the alternate screen"
check "entering the alternate screen clears the attribute" "$SINGLE" "$after" \
      "row $TITLE_ROW kept the attribute from the previous visit to the alternate screen"

# ---------------------------------------------------------------------------
# Case 6: DECSWL. This is the one thing that always cleared the attribute, so it
# doubles as a check that the probe itself is sound.
# ---------------------------------------------------------------------------
reset_screen
printf '\033[%d;1H\033#6Chronicles' "$TITLE_ROW" > /dev/tty
printf '\033[%d;1H\033#5' "$TITLE_ROW" > /dev/tty
after=$(probe_row "$TITLE_ROW")
step "case 6: ESC #5 applied to the double-width row"
say ""
say "Case 6: ESC #5 (DECSWL) on a double-width row"
check "DECSWL clears the attribute" "$SINGLE" "$after" \
      "the probe itself is not measuring what it thinks it is"

# ---------------------------------------------------------------------------
# Informational: EL does not reset the attribute in xterm either, so iTerm2
# keeping it here is correct. Reported, not counted as a failure.
# ---------------------------------------------------------------------------
reset_screen
printf '\033[%d;1H\033#6Chronicles' "$TITLE_ROW" > /dev/tty
printf '\033[%d;1H\033[2K' "$TITLE_ROW" > /dev/tty
after=$(probe_row "$TITLE_ROW")
say ""
if [ "$after" = "$DOUBLE" ]; then
    say "For reference: after CSI 2K the row reports column $after (still double-width,"
    say "which matches xterm, where EL does not reset the attribute either)."
else
    say "For reference: after CSI 2K the row reports column $after (single-width)."
    say "xterm keeps the attribute here, so this is a difference worth knowing about."
fi

# Report. The screen is clean and the tty is back to cooked mode, so this stays
# on screen and scrolls back normally.
reset_screen
cleanup
printf 'iTerm2 issue 13055: stale DECDHL/DECDWL line attribute\n'
printf 'A double-width row reports CPR column %s; a normal row reports %s.\n' "$DOUBLE" "$SINGLE"
for line in "${results[@]}"; do
    printf '%s\n' "$line"
done
printf '\n'
if [ "$failures" -eq 0 ]; then
    printf '\033[32mAll checks passed.\033[m\n'
else
    printf '\033[31m%d check(s) failed.\033[m\n' "$failures"
fi

exit "$failures"
