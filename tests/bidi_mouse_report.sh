#!/bin/bash
# Manual test for mouse reporting on bidi-reordered lines (PR 834).
#
# Setup in iTerm2:
#   Settings > General: turn on “Enable support for right-to-left scripts”.
#   Settings > Advanced > “Auto-detect paragraph writing direction based on
#   the first strong directional character?”: Yes.
#
# Run it, then click or drag across the text. The script draws its own
# highlight at the cells the mouse report names, the way Claude Code does.
# With the fix, the highlight lands under the pointer on every line,
# including the right-justified Persian one. Without it, dragging over the
# Persian text highlights empty cells on the left.
#
# Usage: tests/bidi_mouse_report.sh [-p]
#   -p  Use SGR-Pixels mode (1016) instead of cell mode (1006). Pixel reports
#       are deliberately not remapped, so they show where the pointer is on
#       screen. The highlight is off in this mode; watch the raw numbers.
#
# Press q to quit.

export LC_ALL="${LC_ALL:-en_US.UTF-8}"

PIXELS=0
if [[ "$1" == "-p" ]]; then
    PIXELS=1
fi

# Screen rows (1-based) that hold test lines, and their contents.
ROWS=(4 6 8)
LINES=("سلام دنیا" "hello world" "abc سلام def")

sel_row=0
sel_start=0
sel_end=-1

cleanup() {
    printf '\e[?1002l\e[?1006l\e[?1016l\e[?25h'
    stty "$saved_stty"
    printf '\e[%d;1H\n' 14
}

saved_stty=$(stty -g)
trap cleanup EXIT
stty -echo -icanon min 1 time 0

# Draws one test line. Cells from sel_start to sel_end (0-based logical
# columns) are shown in reverse video if this is the selected row.
draw_line() {
    local i=$1
    local row=${ROWS[$i]}
    local text=${LINES[$i]}
    local out="" c j
    for ((j = 0; j < ${#text}; j++)); do
        c=${text:j:1}
        if [[ $row == "$sel_row" ]] && ((j >= sel_start && j <= sel_end)); then
            out+=$'\e[7m'"$c"$'\e[0m'
        else
            out+="$c"
        fi
    done
    printf '\e[%d;1H\e[2K%s' "$row" "$out"
}

draw_all() {
    local i
    for i in "${!ROWS[@]}"; do
        draw_line "$i"
    done
}

status() {
    printf '\e[11;1H\e[2K%s' "$1"
    printf '\e[12;1H\e[2K%s' "$2"
}

printf '\e[2J\e[?25l\e[1;1H'
if ((PIXELS)); then
    printf 'Pixel mode (1016). Move/click; reports are on-screen pixels. q quits.'
    printf '\e[?1002h\e[?1016h'
else
    printf 'Cell mode (1006). Click or drag across the text. q quits.'
    printf '\e[?1002h\e[?1006h'
fi
draw_all
status "No report yet." ""

while true; do
    IFS= read -rsn1 c
    if [[ $c == q ]]; then
        break
    fi
    [[ $c == $'\e' ]] || continue
    IFS= read -rsn1 c; [[ $c == "[" ]] || continue
    IFS= read -rsn1 c; [[ $c == "<" ]] || continue
    seq=""
    while IFS= read -rsn1 c; do
        if [[ $c == M || $c == m ]]; then
            break
        fi
        seq+="$c"
    done
    IFS=';' read -r b x y <<<"$seq"
    kind="press"
    [[ $c == m ]] && kind="release"
    ((b & 32)) && kind="drag"

    if ((PIXELS)); then
        status "Report: button=$b x=$x y=$y ($kind)" "Pixels are not remapped."
        continue
    fi

    col=$((x - 1))
    line_text=""
    for i in "${!ROWS[@]}"; do
        if ((ROWS[i] == y)); then
            line_text=${LINES[$i]}
        fi
    done
    if [[ -n $line_text ]]; then
        if ((col < ${#line_text})); then
            what="the program thinks the mouse is over “${line_text:col:1}” (logical column $col)"
        else
            what="the program thinks the mouse is past the end of the text (logical column $col)"
        fi
    else
        what="not on a test line"
    fi
    status "Report: button=$b x=$x y=$y ($kind)" "$what"

    case $kind in
        press)
            sel_row=$y
            sel_start=$col
            sel_end=$col
            ;;
        drag)
            if ((y == sel_row)); then
                anchor=${anchor:-$sel_start}
                if ((col < anchor)); then
                    sel_start=$col
                    sel_end=$anchor
                else
                    sel_start=$anchor
                    sel_end=$col
                fi
            fi
            ;;
        release)
            unset anchor
            ;;
    esac
    [[ $kind == press ]] && anchor=$col
    draw_all
done
