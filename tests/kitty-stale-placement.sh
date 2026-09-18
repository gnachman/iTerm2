#!/bin/sh
#
# Reproduces GitLab issue #13028: a stale Kitty virtual placement masks a
# retransmitted image.
#
# It transmits a red 64x64 square as image id 7 with a virtual placement
# (U=1) and references it from a 4x2 grid of U+10EEEE placeholder cells, then
# does the same again under the same id with a green square. Neither display
# command sets a placement id, so both use the default of 0. Each placeholder
# cell carries three diacritics (row, column, image-id MSB=0) to work around the
# separate issue where a missing image-id MSB diacritic is read as -1.
#
# Both placeholder blocks encode image id 7 with the default placement id 0, so both resolve through
# the same (imageID=7, placementID=0) lookup and therefore render the same image. There is no cell
# position in that lookup, so "red then green" is not achievable; the newest image wins for both.
#
# Observed (kitty 0.46): both blocks are green (retransmitting id 7 replaces the bitmap).
# Bug (iTerm2 3.7.0): both blocks are red; the second image never appears.
# Fixed (iTerm2): both blocks are green, matching kitty.
#
# The two PNGs are precomputed and embedded so this stays a pure shell script.

# 64x64 solid squares, generated with the encoder from the issue report.
RED="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeUlEQVR4nO3PQQkAMAzAwAqrfxUTMxF7HINABFzm7H7dcEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFj108cEE8uoIF1wAAAABJRU5ErkJggg=="
GREEN="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfMJEY0pSH8OITBAtxmnf11wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBl0YBLT20X6MAAAAASUVORK5CYII="

ESC=$(printf '\033')
IMAGE_ID=7
COLS=4
ROWS=2

# UTF-8 byte sequences (portable across macOS /bin/sh and zsh).
PH='\xf4\x8e\xbb\xae'                       # U+10EEEE placeholder
D0='\xcc\x85'; D1='\xcc\x8d'; D2='\xcc\x8e'; D3='\xcc\x90'  # rows/cols 0..3

# Third diacritic is the most-significant byte of the image id (7 -> 0 -> D0).
MSB="$D0"

diacritic() {
    case "$1" in
        0) printf '%s' "$D0" ;;
        1) printf '%s' "$D1" ;;
        2) printf '%s' "$D2" ;;
        3) printf '%s' "$D3" ;;
    esac
}

transmit() {
    # $1 = base64 PNG. Emits APC _G ... ST (ESC \).
    printf '%s_Ga=T,f=100,t=d,i=%d,U=1,c=%d,r=%d,q=2;%s%s\\' \
        "$ESC" "$IMAGE_ID" "$COLS" "$ROWS" "$1" "$ESC"
}

placeholder_rows() {
    row=0
    while [ "$row" -lt "$ROWS" ]; do
        printf '%s[38;2;0;0;%dm' "$ESC" "$IMAGE_ID"
        rd=$(diacritic "$row")
        col=0
        while [ "$col" -lt "$COLS" ]; do
            cd=$(diacritic "$col")
            printf '%b%b%b%b' "$PH" "$rd" "$cd" "$MSB"
            col=$((col + 1))
        done
        printf '%s[0m\n' "$ESC"
        row=$((row + 1))
    done
}

block() {
    # $1 = label, $2 = base64 PNG
    printf -- '--- id=%d: %s ---\n' "$IMAGE_ID" "$1"
    transmit "$2"
    placeholder_rows
    printf '\n'
}

block "first transmission, red" "$RED"
block "second transmission, green" "$GREEN"
