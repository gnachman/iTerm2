#!/bin/sh
#
# Records what a terminal does to an EXISTING non-virtual Kitty placement when its image id is
# retransmitted with a new bitmap. This is the scrollback case that issue 13028's follow-up left
# unverified against real kitty.
#
# It displays a red 64x64 square as image id 7 directly at the cursor (a non-virtual placement, no
# U=1), prints some blank lines to separate it, then transmits AND displays a green square under the
# same id 7. Watch the FIRST (upper) square after the second command runs.
#
# Possible outcomes for the first (upper) square:
#   - STAYS RED   => the terminal treats a non-virtual placement as a snapshot and does not rewrite
#                    already-drawn pictures. This is what fixed iTerm2 does (repointPlacements only
#                    re-points virtual placements).
#   - TURNS GREEN => the terminal re-points every placement of the id to the newest bitmap, collapsing
#                    scrollback history. This was iTerm2's behavior before the fix.
#   - DISAPPEARS  => the terminal frees the old image on retransmit (kitty's handle_add_command frees
#                    the previous image for an existing id), so old placements can no longer render.
#
# If kitty 0.46 DISAPPEARS the first square, repointPlacements should REMOVE non-virtual placements of
# a retransmitted id rather than leave them showing the old bitmap.
#
# The two PNGs are precomputed and embedded so this stays a pure shell script.

# 64x64 solid squares.
RED="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeUlEQVR4nO3PQQkAMAzAwAqrfxUTMxF7HINABFzm7H7dcEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFj108cEE8uoIF1wAAAABJRU5ErkJggg=="
GREEN="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfMJEY0pSH8OITBAtxmnf11wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBl0YBLT20X6MAAAAASUVORK5CYII="

ESC=$(printf '\033')

display() {
    # $1 = base64 PNG. a=T transmit and display (non-virtual: no U key), at the cursor.
    printf '%s_Ga=T,f=100,t=d,i=7,q=2;%s%s\\' "$ESC" "$1" "$ESC"
}

printf 'Step 1: display a RED square as image id 7 at the cursor.\n'
display "$RED"
printf '\n\n\n\n\n'
printf 'Press Enter to retransmit image id 7 as a GREEN square below...'
read -r _
display "$GREEN"
printf '\n\nNow look at the FIRST (upper) square:\n'
printf '  STAYS RED   -> non-virtual placements are snapshots (fixed iTerm2).\n'
printf '  TURNS GREEN -> scrollback collapsed to the newest bitmap (iTerm2 before the fix).\n'
printf '  DISAPPEARS  -> the old image was freed on retransmit (possible kitty behavior).\n'
