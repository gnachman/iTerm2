#!/bin/bash
# Exercises the edge cases that historically forced iTerm2 to redraw whole rows
# (or the whole view) in the legacy renderer. Use this to stress-test the
# per-line dirty-rect path:
#   - Descenders that spill out of a line into the line below
#     (issue 6223 / commit 36cfd509d, and the original ±1-row halo)
#   - Tall ascenders/brackets that spill into the line above
#   - Ligature “spooky action at a distance” like Fira Code <*> or ->->->->
#     (issues 5030 / 7461, commits 7ba38cf7a, cae1ac8d9, e40f933f9)
#   - Bismillah ﷽ and wide horizontally-extending glyphs
#   - VS15/VS16 emoji presentation that depends on adjacent characters
#     (issue 9185, commit 28618b3c5)
#   - Italics/fake-italics/fake-bold spill into neighbor cells
#     (commit fd7d3939c)
#   - Combining marks
#     (commit ed8e25447)
#   - Wide CJK chars
#   - Box-drawing glyphs (their own bezier draw path)
#   - Claude Code-style spinner as a baseline (issue 12790)
#
# Usage:
#   tests/redraw-edge-cases.sh [interval_seconds]
# Default interval: 0.2s. Ctrl-C to exit.
#
# Recommended companion:
#   defaults write com.googlecode.iterm2 \
#       showDirtyRectsInLegacyRenderer -bool YES
#   ...then restart iTerm2 and turn off Metal (Prefs › General › Magic).
#   Each redraw will be flashed red and outlined in a random color so you can
#   see which rows are getting repainted.

interval="${1:-0.2}"

# Hide cursor and ensure we re-show it on exit.
printf '\033[?25l'
cleanup() { printf '\033[?25h\n'; exit 0; }
trap cleanup INT TERM EXIT

# Number of test rows including the trailing instruction lines.
ROWS=16

print_block() {
    cat <<'EOF'
─── PER-LINE REDRAW EDGE CASES ────────────────────────────────────────
 1 anchor   gypqjygypqjygypqjy   (descenders into the row below)
 2 animate  ▶                                                        ◀
 3 anchor   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   (filled cells: ghost spotting)
 4 animate  ▶                                                        ◀
 5 animate  ▶                                                        ◀
 6 animate  ▶                                                        ◀
 7 animate  ▶                                                        ◀
 8 animate  ▶                                                        ◀
 9 animate  ▶                                                        ◀
10 animate  ▶                                                        ◀
11 animate  ▶                                                        ◀
12 animate  ▶                                                        ◀
13 anchor   {[(jpqgy)]}/|\jpqgy  (mixed ascenders + descenders)
14 anchor   yyyyyyyyyyyyyyyyyy   (descenders into empty space)
 watch for orphaned descender pixels, broken ligatures, half-erased wide
 glyphs, missing accents, baseline shifts. Ctrl-C to exit.
EOF
}

# Print the block, then move cursor back to the top of it so we can address
# rows by line number.
print_block
printf '\033[%dA' "$ROWS"
# Save the “top of block” cursor position.
printf '\0337'

# Move the cursor to a given row (1-based) inside the block, then to column 13
# (right after the “NN animate  ▶ ” label).
goto_row() {
    printf '\0338'                # restore cursor to top-of-block
    if [ "$1" -gt 1 ]; then
        printf '\033[%dB' "$(($1 - 1))"
    fi
    printf '\r\033[13C'           # column 13 (after the “▶” marker)
}

# Print a fixed-width animation cell, then the “◀” right marker at column 70.
# This both writes the new content and ensures any leftover pixels from the
# previous variant are pushed out by the trailing spaces.
print_cell() {
    local s="$1"
    # Pad/truncate to a known width by clearing to end of line first, writing
    # the content, then redrawing the right-edge marker.
    printf '\033[K%s' "$s"
    # Move to column 70 and draw the right marker.
    printf '\r\033[69C◀'
}

# Animation variants. Each lane cycles between two variants on every tick.
# Lane indexes correspond to “animate” rows in print_block above.
declare -a VARIANT_A VARIANT_B LABEL_AT VARIANT_NOTE
VARIANT_A[2]="gypqj gypqj gypqj gypqj gypqj"   # descenders
VARIANT_B[2]="aaaaa aaaaa aaaaa aaaaa aaaaa"   # nothing below baseline
VARIANT_NOTE[2]="descender ghosting"

VARIANT_A[4]="^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"  # tops-only chars
VARIANT_B[4]="MMMMMMMMMM jjjjjjjjjj"           # has full-height + descenders
VARIANT_NOTE[4]="ascender/descender mix"

VARIANT_A[5]="-> -> -> -> -> -> -> -> ->"      # ligature candidate (Fira/etc)
VARIANT_B[5]="===> ===> ===> ===> ===> ===>"   # different ligature
VARIANT_NOTE[5]="ligature spooky action"

VARIANT_A[6]="text ﷽ text ﷽ text"              # bismillah, very wide
VARIANT_B[6]="text X text X text X text X"     # narrow replacement
VARIANT_NOTE[6]="bismillah / wide cluster"

VARIANT_A[7]="heart ❤️ heart ❤️ heart"         # VS16 emoji presentation
VARIANT_B[7]="heart ❤︎ heart ❤︎ heart"         # VS15 text presentation
VARIANT_NOTE[7]="VS15/VS16 toggle"

VARIANT_A[8]=$'\033[3mitalic mmm jjj qqq\033[0m'   # italics with descenders
VARIANT_B[8]="regular mmm jjj qqq"                   # no italics
VARIANT_NOTE[8]="italic horizontal spill"

VARIANT_A[9]="a̐ e̊ i̧ õ ṷ a̐ e̊ i̧ õ ṷ a̐"           # combining marks
VARIANT_B[9]="a e i o u a e i o u a e i o u"        # plain
VARIANT_NOTE[9]="combining marks"

VARIANT_A[10]="ＷＩＤＥ ＣＨＡＲＳ ＨＥＲＥ"       # full-width CJK
VARIANT_B[10]="narrow ascii ascii ascii"           # half-width
VARIANT_NOTE[10]="wide CJK"

VARIANT_A[11]="┌─┬─┬─┐ ╔═╦═╗ ┊╳╳╳"               # box drawing
VARIANT_B[11]="+-+-+-+ +-+-+ |xxx"                 # plain ASCII
VARIANT_NOTE[11]="box drawing path"

# Lane 12: Claude Code-style spinner. Single variant that updates each tick.
VARIANT_NOTE[12]="Claude Code-style baseline"

glyphs=('✻' '✺' '✹' '✸' '✷')
labels=('Symbioting' 'Pondering' 'Synthesizing' 'Juggling' 'Ruminating')

# Update exactly one row per tick (round-robin). Updating multiple rows in a
# single tick would let iTerm2 union them into one big dirty rect and the
# per-line halo path would never get exercised — we'd just see a wide redraw
# every frame, regardless of whether per-line invalidation is correct.
ANIMATED_ROWS=(2 4 5 6 7 8 9 10 11 12)
declare -A LANE_TICK
for row in "${ANIMATED_ROWS[@]}"; do LANE_TICK[$row]=0; done

tick=0
start=$(date +%s)

while :; do
    # Choose which lane to update this tick.
    lane_index=$((tick % ${#ANIMATED_ROWS[@]}))
    row="${ANIMATED_ROWS[$lane_index]}"
    lane_tick="${LANE_TICK[$row]}"

    if [ "$row" -eq 12 ]; then
        # Claude Code-style spinner — fresh content every visit.
        glyph="${glyphs[$((lane_tick % ${#glyphs[@]}))]}"
        label="${labels[$((lane_tick % ${#labels[@]}))]}"
        now=$(date +%s)
        elapsed=$((now - start))
        tokens=$((lane_tick * 73 % 9999))
        content="$(printf '%s %s… (%ds · %d tokens · jiggly puppy)' \
                   "$glyph" "$label" "$elapsed" "$tokens")"
    else
        if [ $((lane_tick & 1)) -eq 0 ]; then
            content="${VARIANT_A[$row]}"
        else
            content="${VARIANT_B[$row]}"
        fi
    fi

    goto_row "$row"
    print_cell "$content"

    # Park the real cursor below the block so user-typed shell prompts after
    # Ctrl-C don't overlap our diagram.
    printf '\0338'
    printf '\033[%dB\r' "$ROWS"

    LANE_TICK[$row]=$((lane_tick + 1))
    tick=$((tick + 1))
    sleep "$interval"
done
