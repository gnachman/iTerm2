#!/bin/bash
# Mimics the Claude Code spinner update pattern for testing the legacy-renderer
# per-line redraw path. Overwrites a single line ~5 times per second with a
# rotating glyph and a token counter. Includes a few descender characters
# (g, y, p, q, j) so the ±1 row dirty halo gets exercised.
#
# Usage: tests/spinner.sh [interval_seconds]
# Default interval: 0.2s (5 Hz). Ctrl-C to stop.

interval="${1:-0.2}"

glyphs=('✻' '✺' '✹' '✸' '✷')
labels=('Symbioting' 'Pondering' 'Synthesizing' 'Marshaling' 'Wrangling' 'Juggling' 'Ruminating' 'Querying')

start=$(date +%s)
i=0
trap 'printf "\n"; exit 0' INT

# Hide the cursor for a closer match to a TUI app.
printf '\033[?25l'
trap 'printf "\033[?25h\n"; exit 0' INT

while :; do
    glyph="${glyphs[$((i % ${#glyphs[@]}))]}"
    label="${labels[$((i % ${#labels[@]}))]}"
    now=$(date +%s)
    elapsed=$((now - start))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    tokens=$((i * 73 % 9999))
    # Carriage return overwrite, no newline. The line contains descenders
    # (g, y, p, q, j) to exercise the dirty-rect halo on the legacy renderer.
    printf '\r%s %s… (%dm %ds · ↑ %d tokens, jiggly puppy)        ' \
        "$glyph" "$label" "$minutes" "$seconds" "$tokens"
    i=$((i + 1))
    sleep "$interval"
done
