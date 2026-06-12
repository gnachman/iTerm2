#!/bin/sh
# Manual test for dual-mode SGR underline color (issue #12838).
#
# Mirrors tests/dual-mode-color.sh: each line emits a universal-fallback
# 58:5 / 58:2 first, then chains the colon-form dual-mode override
# (light variant first, dark variant second). Toggle macOS appearance
# (or switch to a profile with the opposite background brightness) and
# watch the underline color swap.

ESC=$(printf '\033')

# Curly underline (SGR 4:3) makes the color shift more visible than a
# straight single underline.
CURLY="${ESC}[4:3m"
RESET="${ESC}[0m"

# 24-bit dual-mode underline (red light variant / blue dark variant)
printf '%s%s[58:2:200:0:0m%s[58:12:200:0:0:80:140:255m24-bit dual underline (red on light bg, blue on dark)%s\n' \
    "$CURLY" "$ESC" "$ESC" "$RESET"

# 256-mode dual-mode underline (orange light, green dark)
printf '%s%s[58:5:208m%s[58:13:208:42m256-color dual underline (208 on light bg, 42 on dark)%s\n' \
    "$CURLY" "$ESC" "$ESC" "$RESET"

# Combined: dual-mode foreground + dual-mode underline color, curly style.
printf '%s%s[38;2;128;0;0m%s[38:12:128:0:0:255:200:200m%s[58:2:200:0:0m%s[58:12:200:0:0:80:140:255mDual FG + dual underline%s\n' \
    "$CURLY" "$ESC" "$ESC" "$ESC" "$ESC" "$RESET"

# Reset (SGR 59) check: a single-color 58 followed by 59 must clear.
printf '%s%s[58:2:255:0:0mUnderline red%s[59m, then default after reset%s\n' \
    "$CURLY" "$ESC" "$ESC" "$RESET"

echo
echo "Toggle macOS appearance (System Settings > Appearance, or change profile)"
echo "and watch the underline colors above swap between light and dark variants."
