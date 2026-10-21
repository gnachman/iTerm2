#!/bin/bash
# Demonstrates issue 13146: with the GPU renderer, a direct Kitty placement
# whose source rectangle is cropped vertically (y=, h=) shows the mirrored
# band of the image.
#
# Shows the image uncropped on the left. On the right, rebuilds it from
# horizontal strips, each one its own placement with a y=/h= crop, the way
# herdr forwards multi-row images. With the bug, the strips on the right come
# out in reverse order. With the legacy renderer (turn on “Use ligatures”)
# both copies match.
#
# Run it directly in iTerm2, not in tmux. Usage: kitty-crop-bulldog.sh [image]

set -euo pipefail

SRC=${1:-$HOME/bulldog.jpg}
STRIPS=5
COLS=40
ROWS_PER_STRIP=2
ROWS=$((STRIPS * ROWS_PER_STRIP))
IMAGE_ID=13146

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PNG="$TMP/image.png"
sips -s format png -Z 400 "$SRC" --out "$PNG" > /dev/null
HEIGHT=$(sips -g pixelHeight "$PNG" | awk '/pixelHeight/ { print $2 }')

apc() {
    printf '\e_G%s\e\\' "$1"
}

printf '\e[2J\e[H'

# Upload the PNG in 4096-byte base64 chunks.
CHUNKS=()
while IFS= read -r chunk; do
    CHUNKS+=("$chunk")
done < <(base64 -i "$PNG" | tr -d '\n' | fold -w 4096)
LAST=$((${#CHUNKS[@]} - 1))
for i in "${!CHUNKS[@]}"; do
    MORE=1
    if [ "$i" -eq "$LAST" ]; then
        MORE=0
    fi
    if [ "$i" -eq 0 ]; then
        apc "a=t,f=100,i=$IMAGE_ID,q=2,m=$MORE;${CHUNKS[$i]}"
    else
        apc "m=$MORE,q=2;${CHUNKS[$i]}"
    fi
done

printf '\e[1;2HUncropped'
printf '\e[1;%dHRebuilt from %d cropped strips' $((COLS + 5)) "$STRIPS"

printf '\e[2;2H'
apc "a=p,i=$IMAGE_ID,p=1,c=$COLS,r=$ROWS,C=1,q=2"

STRIP_HEIGHT=$((HEIGHT / STRIPS))
for ((s = 0; s < STRIPS; s++)); do
    Y=$((s * STRIP_HEIGHT))
    H=$STRIP_HEIGHT
    if [ "$s" -eq $((STRIPS - 1)) ]; then
        H=$((HEIGHT - Y))
    fi
    printf '\e[%d;%dH' $((2 + s * ROWS_PER_STRIP)) $((COLS + 5))
    apc "a=p,i=$IMAGE_ID,p=$((s + 2)),y=$Y,h=$H,c=$COLS,r=$ROWS_PER_STRIP,C=1,q=2"
    printf '\e[%d;%dHy=%d,h=%d' $((2 + s * ROWS_PER_STRIP)) $((2 * COLS + 7)) "$Y" "$H"
done

printf '\e[%d;1H' $((ROWS + 3))
echo "If the right side shows the strips in reverse order, the bug is present."
