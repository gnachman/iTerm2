#!/bin/sh
# Manual test for dual-mode SGR colors (issue #12832).
#
# Each line emits a universal-truecolor fallback first, then chains the
# colon-form dual-mode override (light variant first, dark variant second).
# In iTerm2, toggle macOS appearance and watch each line's color flip.
# In a non-supporting terminal, only the fallback color appears.

ESC=$(printf '\033')

# CSI 38;2;Rf;Gf;Bf m   universal fallback
# CSI 38:12:Rl:Gl:Bl:Rd:Gd:Bd m   dual-mode RGB foreground

emit() {
    label=$1
    fallback=$2
    light=$3
    dark=$4
    printf "%s[%sm%s [fallback %s, light %s, dark %s]%s[0m\n" \
        "$ESC" "$fallback;$ESC[$light" "$label" "$fallback" "$light" "$dark" "$ESC"
}

# 24-bit dual-mode foreground
printf '%s[38;2;255;0;0m%s[38:12:200:0:0:255:200:200mDual-mode FG (dark red light / pink dark)%s[0m\n' "$ESC" "$ESC" "$ESC"

# 24-bit dual-mode background
printf '%s[48;2;255;255;0m%s[48:12:255:255:0:30:30:80mDual-mode BG (yellow light / navy dark)%s[0m\n' "$ESC" "$ESC" "$ESC"

# 256-mode dual-mode foreground (orange light, green-ish dark)
printf '%s[38;5;208m%s[38:13:208:120mDual-mode 256-mode FG (208 light / 120 dark)%s[0m\n' "$ESC" "$ESC" "$ESC"

# Combined dual fg + dual bg
printf '%s[38;2;0;0;128m%s[38:12:0:0:128:200:200:255m%s[48;2;255;230;200m%s[48:12:255:230:200:30:30:50mDual FG + Dual BG%s[0m\n' "$ESC" "$ESC" "$ESC" "$ESC" "$ESC"

echo
echo "Toggle macOS appearance (System Settings > Appearance, or via shortcut)"
echo "and watch the colors above swap between their light and dark variants."
