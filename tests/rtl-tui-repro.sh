#!/bin/bash
# Emulates how a TUI (like Claude Code) writes streaming RTL output:
# print a Persian paragraph, then repeatedly repaint it in place
# (cursor up + erase line + rewrite, with styled segments), then let
# it scroll into history. With bidi enabled, all four copies below
# must render identically (right-justified, correct RTL order). If
# the repainted copies render in logical order (visually reversed)
# while the plain-printed ones are correct, the bug reproduces.
#
# Usage: run in an iTerm2 window with RTL support enabled and watch
# the output. The window should be at least 60 columns wide.

L1='داشتیم به فارسی درباره آبوهوا و برنامه آخر هفته برلین صحبت می‌کردیم.'
L2='جشنواره British Shorts Summer Edition تا یکشنبه ادامه دارد و هوا حدود ۲۵ درجه است.'
L3='فستیوال فرهنگ و غذای ژاپنی Hikari Japan Festival فقط شنبه است.'

echo "=== PLAIN (control): printed once, never repainted ==="
printf '%s\n%s\n%s\n' "$L1" "$L2" "$L3"
echo

echo "=== REPAINTED: rewritten in place 5 times ==="
printf '%s\n%s\n%s\n' "$L1" "$L2" "$L3"
for i in 1 2 3 4 5; do
    sleep 0.1
    # Cursor up 3 rows, then erase and rewrite each row.
    printf '\033[3A'
    printf '\r\033[2K%s\n' "$L1"
    printf '\r\033[2K%s\n' "$L2"
    printf '\r\033[2K%s\n' "$L3"
done
echo

echo "=== SEGMENTED: each row written as styled pieces ==="
printf '\033[1m%s\033[0m %s \033[2m%s\033[0m\n' 'جشنواره' 'British Shorts Summer Edition' 'تا یکشنبه ادامه دارد.'
printf '\033[33m%s\033[0m %s\n' 'فستیوال ژاپنی' 'Hikari Japan Festival فقط شنبه است.'
echo

echo "=== SCROLLED: repainted rows pushed into scrollback ==="
printf '%s\n%s\n' "$L1" "$L2"
sleep 0.1
printf '\033[2A\r\033[2K%s\n\r\033[2K%s\n' "$L1" "$L2"
for i in $(seq 1 3); do echo; done
echo "(scroll up: the two rows above must still read correctly)"
