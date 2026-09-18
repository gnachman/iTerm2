#!/bin/sh
#
# Verifies how a terminal resolves a Kitty image source crop (x/y/w/h) when the image is
# retransmitted under the same id with a DIFFERENT-sized bitmap.
#
# Open question (issue 13028 follow-up): kitty appears to normalize the source rectangle to
# fractions of the image at ref-creation time (ImageRef.src_rect in graphics.c), so on a retransmit
# to a smaller bitmap it samples the same PROPORTIONAL region. iTerm2 currently stores the raw
# absolute-pixel request and clamps it to the current bitmap, so a crop whose origin falls outside
# the new (smaller) bitmap collapses and it falls back to the whole image.
#
# What this script does:
#   1. Transmits image id 7 as a 64x64 four-quadrant image (TL red, TR green, BL blue, BR yellow)
#      and displays it as a virtual placement cropped to the bottom-right quadrant
#      (x=32,y=32,w=32,h=32). A 4x2 Unicode-placeholder grid renders that crop.
#   2. Retransmits image id 7 as a 32x32 four-quadrant image (TL cyan, TR magenta, BL orange,
#      BR white) with a bare transmit (a=t, no new display command), so the existing placement's
#      stored crop is reused against the new bitmap.
#
# How to read the result (the block updates in place after step 2):
#   - SOLID WHITE  => the crop was normalized to fractions and sampled the bottom-right quadrant of
#                     the new 32x32 bitmap (white). This is kitty's behavior, and it is what fixed
#                     iTerm2 now does too (Placement.SourceRegion stores fractions).
#   - FOUR COLORS  => an absolute-pixel crop (32,32,32,32) collapsed on the 32x32 bitmap and the
#     (cyan/magenta/    whole new image is shown. This was iTerm2's behavior BEFORE the fix.
#      orange/white)
#   - STILL YELLOW / unchanged => the terminal did not re-point the placement at the new bitmap on a
#                     bare a=t at all (a separate question from src_rect semantics).
#
# Use this to confirm kitty 0.46 shows SOLID WHITE (normalized). If it instead shows FOUR COLORS,
# kitty uses absolute pixels and the normalization in KittyImageController should be reverted.
#
# The two PNGs are precomputed and embedded so this stays a pure shell script.

# 64x64: TL red, TR green, BL blue, BR yellow.
IMG64="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAX0lEQVR4nO3PMQ0AIAwAMOQgYkomESUTwY0ONOzY16QGum7EqDg5agkICAgICAgICAgICAgICAgICAgICAgItAORNerVHiUgICAgICAgICAgICAgICAgICAgICAg0PYB6c4hWsezFrcAAAAASUVORK5CYII="
# 32x32: TL cyan, TR magenta, BL orange, BR white.
IMG32="iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAN0lEQVR4nO3NMQ0AAAgDQeRULMKqBAfsaOhI8s2PTa5kR2VvuQAAAAAAXgDTitpwAAAAAAAvgAOYu+lqa4yY3QAAAABJRU5ErkJggg=="

ESC=$(printf '\033')
IMAGE_ID=7
COLS=4
ROWS=2

# UTF-8 byte sequences (portable across macOS /bin/sh and zsh).
PH='\xf4\x8e\xbb\xae'                       # U+10EEEE placeholder
D0='\xcc\x85'; D1='\xcc\x8d'; D2='\xcc\x8e'; D3='\xcc\x90'  # rows/cols 0..3
MSB="$D0"                                    # image-id MSB diacritic (7 -> 0 -> D0)

diacritic() {
    case "$1" in
        0) printf '%s' "$D0" ;;
        1) printf '%s' "$D1" ;;
        2) printf '%s' "$D2" ;;
        3) printf '%s' "$D3" ;;
    esac
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

printf 'Step 1: display image id 7 (64x64), cropped to its bottom-right quadrant.\n'
# a=T transmit and display, U=1 virtual placement, c/r placeholder grid, x/y/w/h source crop.
printf '%s_Ga=T,f=100,t=d,i=%d,U=1,c=%d,r=%d,x=32,y=32,w=32,h=32,q=2;%s%s\\' \
    "$ESC" "$IMAGE_ID" "$COLS" "$ROWS" "$IMG64" "$ESC"
placeholder_rows
printf 'Expected now: a SOLID YELLOW block (the bottom-right quadrant of the 64x64 image).\n'
printf 'Press Enter to retransmit image id 7 as a 32x32 four-color bitmap...'
read -r _

# a=t transmit only (no display command); replaces the bitmap for image id 7.
printf '%s_Ga=t,f=100,t=d,i=%d,q=2;%s%s\\' "$ESC" "$IMAGE_ID" "$IMG32" "$ESC"

printf '\n\nThe block above should have updated in place. Compare:\n'
printf '  SOLID WHITE          -> crop normalized to the new bitmap (kitty src_rect is fractional).\n'
printf '  FOUR COLORS          -> absolute-pixel crop collapsed to the whole image (iTerm2 current).\n'
printf '  (cyan/magenta/orange/white)\n'
printf '  UNCHANGED (yellow)   -> the terminal did not re-point the placement on a bare a=t.\n'
