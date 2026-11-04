#!/bin/bash
# Repro for the flicker fixer losing a full redraw.
#
# Each frame ends a synchronized update and begins the next one in the same
# write (CSI ? 2026 l, CSI ? 2026 h). Ending it expires the saved grid, which
# asks for every row to be repainted. Beginning the next one in the same write
# takes a new saved grid before any sync, and the copy drops that request. Rows
# that changed while the previous saved grid was on screen are never repainted.
#
# Use the legacy renderer (turn off GPU rendering) to see it.
#
# Expected (fixed): the counter below counts up, one frame behind.
# Bug: the counter area stays blank until the script ends, then jumps to the
# final value.

frames=${1:-40}

printf '\e[2J\e[H'
printf 'Watch the counter on the next line. It should count up to %d.\n' "$frames"

for ((i = 1; i <= frames; i++)); do
    # Expire the current saved grid and take a new one before the next sync.
    printf '\e[?2026l\e[?2026h'
    # Give a sync time to draw the new saved grid.
    sleep 0.1
    # Change the screen while the saved grid is on screen.
    printf '\e[3;1H\e[2Kcounter: %d' "$i"
    # Give a sync time to copy the change to the main thread.
    sleep 0.1
done

printf '\e[?2026l'
printf '\e[5;1HDone.\n'
