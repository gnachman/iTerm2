#!/usr/bin/env bash
#
# cursor-smart-color-probe.sh
#
# Interactively probe iTerm2's "Context-aware cursor color" (aka Smart Cursor
# Color) box-cursor logic. It draws a single target character and lets you vary:
#
#   - the target's FOREGROUND color (the value the smart cursor derives its box
#     color from), and
#   - the eight NEIGHBOR cells around the cursor (their background color, and
#     whether they are painted spaces, erased NULL cells, visible glyphs, or
#     left at the profile default).
#
# The block cursor is then parked on the target so you can watch what color the
# cursor box becomes. The point is to reproduce the reporter's green<->white (or
# white<->gray) behavior, which depends on neighbor cell attributes that are not
# visible on screen or in a screen recording.
#
# Prerequisites in the active iTerm2 profile:
#   - Colors tab: "Context-aware cursor color (affects box cursor only)" ON
#   - Text/Terminal: cursor style = Box, and "Blinking cursor" ON if you want to
#     watch the fade. The steady color is visible either way.
#
# Controls:
#   f / F   next / previous target foreground color
#   b / B   next / previous neighbor background color
#   t       cycle neighbor content: space -> null(ECH) -> glyph -> (default)
#   p       cycle which neighbors are painted: all -> L/R -> U/D -> right -> none
#   space   redraw / re-park the cursor
#   q       quit

set -u

esc=$'\033'

# Target cell location (1-based row/col).
TR=8
TC=24

# --- color tables: "R G B  label" (label may contain spaces) ---------------
FGS=(
  "47 94 0 #2f5e00  brightness .27"
  "94 188 0 #5ebc00  brightness .55"
  "0 200 0 pure-ish green  brightness .46"
  "128 255 0 #80ff00  brightness .74"
  "180 180 180 light gray  brightness .70"
)

# The literal string "default" means: emit no background (use the profile's
# default background) so the neighbor is a genuinely-default cell.
BGS=(
  "default"
  "0 0 0 explicit black"
  "24 24 24 #181818"
  "48 48 48 #303030"
  "96 96 96 #606060"
  "160 160 160 #a0a0a0"
  "255 255 255 white"
  "47 94 0 same as fg #2f5e00"
  "0 48 96 #003060"
)

TYPES=(space null glyph default)
PLACEMENTS=(all lr ud right none)

fi=0   # foreground index
bi=0   # neighbor background index
ti=0   # neighbor type index
pi=0   # placement index

cup() { printf '%s[%d;%dH' "$esc" "$1" "$2"; }
reset_sgr() { printf '%s[0m' "$esc"; }
set_fg() { printf '%s[38;2;%d;%d;%dm' "$esc" "$1" "$2" "$3"; }
set_bg() { printf '%s[48;2;%d;%d;%dm' "$esc" "$1" "$2" "$3"; }

cleanup() {
  reset_sgr
  printf '%s[?25h' "$esc"   # show cursor
  cup 24 1
  printf '\n'
}
trap cleanup EXIT INT TERM

# Paint one neighbor cell at (row,col) using the current background+type.
paint_neighbor() {
  local row=$1 col=$2
  local bg_entry="${BGS[$bi]}"
  cup "$row" "$col"
  if [[ "$bg_entry" == "default" ]]; then
    reset_sgr
  else
    read -r r g b _label <<<"$bg_entry"
    set_bg "$r" "$g" "$b"
  fi

  case "${TYPES[$ti]}" in
    space)   printf ' ' ;;
    null)    printf '%s[1X' "$esc" ;;               # ECH: erase to NULL, keep bg attr
    glyph)   set_fg 200 200 200; printf 'x' ;;      # a visible neighbor glyph
    default) : ;;                                   # leave the cell untouched
  esac
  reset_sgr
}

should_paint() {
  local dr=$1 dc=$2
  case "${PLACEMENTS[$pi]}" in
    all)   [[ $dr -ne 0 || $dc -ne 0 ]] ;;
    lr)    [[ $dr -eq 0 && $dc -ne 0 ]] ;;
    ud)    [[ $dc -eq 0 && $dr -ne 0 ]] ;;
    right) [[ $dr -eq 0 && $dc -eq 1 ]] ;;
    none)  return 1 ;;
  esac
}

draw() {
  printf '%s[2J' "$esc"      # clear screen
  reset_sgr

  read -r fr fg fb fg_label <<<"${FGS[$fi]}"

  cup 2 2;  printf 'Context-aware cursor color probe'
  cup 3 2;  printf 'target fg   : %d %d %d  (%s)' "$fr" "$fg" "$fb" "$fg_label"
  cup 4 2;  printf 'neighbor bg : %s' "${BGS[$bi]}"
  cup 5 2;  printf 'neighbor typ: %s     painted: %s' "${TYPES[$ti]}" "${PLACEMENTS[$pi]}"
  cup 6 2;  printf 'keys: f/F fg  b/B bg  t type  p placement  space redraw  q quit'

  # Paint the 3x3 neighborhood (center is the target, skipped here).
  local dr dc
  for dr in -1 0 1; do
    for dc in -1 0 1; do
      if [[ $dr -eq 0 && $dc -eq 0 ]]; then continue; fi
      if should_paint "$dr" "$dc"; then
        paint_neighbor $((TR + dr)) $((TC + dc))
      fi
    done
  done

  # Paint the target character with the chosen foreground and default bg.
  cup "$TR" "$TC"
  set_fg "$fr" "$fg" "$fb"
  printf 'A'
  reset_sgr

  # A labeled pointer so you know which cell to watch.
  cup $((TR + 3)) $((TC - 6)); printf 'watch the box cursor on "A" above'

  # Park the real cursor on the target so the box cursor renders there.
  cup "$TR" "$TC"
}

printf '%s[?25h' "$esc"
draw
while true; do
  IFS= read -rsn1 key || break
  case "$key" in
    f) fi=$(((fi + 1) % ${#FGS[@]})) ;;
    F) fi=$(((fi - 1 + ${#FGS[@]}) % ${#FGS[@]})) ;;
    b) bi=$(((bi + 1) % ${#BGS[@]})) ;;
    B) bi=$(((bi - 1 + ${#BGS[@]}) % ${#BGS[@]})) ;;
    t) ti=$(((ti + 1) % ${#TYPES[@]})) ;;
    p) pi=$(((pi + 1) % ${#PLACEMENTS[@]})) ;;
    q) break ;;
    *) : ;;   # any other key (incl. Enter) just redraws
  esac
  draw
done
