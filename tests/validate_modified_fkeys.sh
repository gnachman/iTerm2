#!/usr/bin/env bash
#
# validate_modified_fkeys.sh
#
# Manual validation for iTerm2 issue 10717: modified function keys (Shift+F5,
# Ctrl+F5, etc.) must keep their modifier inside a tmux -CC integration session,
# sending the xterm form (e.g. ^[[15;2~) rather than the bare unmodified
# sequence (^[[15~).
#
# HOW TO USE
#   1. Build/run the iTerm2 you want to test.
#   2. Remove any per-key profile overrides you added as a workaround for F1-F4
#      (Preferences > Profiles > Keys), or they will mask what iTerm2 emits.
#   3. Open a tmux -CC session, e.g.
#          ssh myhost -t -- "tmux -CC new -A -s validate"
#      and run this script inside it. Press each key it asks for.
#   4. For a side-by-side baseline, run it again in a PLAIN session (no -CC,
#      e.g. a local shell or a normal ssh). After the fix the two runs should
#      report the same bytes for every key.
#
# Pass --show to skip the guided checklist and just print the bytes for any key
# you press (Ctrl-C to quit) -- handy as a self-contained `cat -v`.
#
# Notes
#   * F1-F4 send SS3 sequences (^[OP..^[OS) when unmodified and CSI sequences
#     (^[[1;2P..) when modified; F5+ use CSI (^[[15~ / ^[[15;2~) throughout.
#   * If macOS steals F1-F4 (brightness, etc.), enable "Use F1, F2, etc. keys
#     as standard function keys" or hold Fn while pressing them.
#   * Inside tmux, forwarding the modifier also requires tmux to recognize the
#     extended sequence (modern tmux does this by default; on older configs you
#     may need `set -g extended-keys on`). A mismatch there is a tmux setting,
#     not the iTerm2 bug this validates -- the plain-session comparison in step 4
#     disambiguates the two.

set -u

DRAIN=${DRAIN:-0.15}   # seconds to wait for the rest of an escape burst

# Render a raw byte string as caret notation (^[ for ESC, ^X for control, etc.).
caret() {
    local s=$1 out="" i c code
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        printf -v code '%d' "'$c"
        if (( code < 32 )); then
            printf -v esc '\\%03o' $(( code + 64 ))
            # shellcheck disable=SC2059
            out+="^$(printf "$esc")"
        elif (( code == 127 )); then
            out+="^?"
        else
            out+=$c
        fi
    done
    printf '%s' "$out"
}

# Render a raw byte string as space-separated hex.
hexdump_str() {
    local s=$1 out="" i c
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        printf -v byte '%02x' "'$c"
        out+="$byte "
    done
    printf '%s' "${out% }"
}

# Read one keypress worth of bytes: block for the first byte, then drain any
# that follow within DRAIN seconds (the rest of an escape sequence).
read_seq() {
    local first c
    IFS= read -rsn1 first || return 1
    local seq=$first
    while IFS= read -rsn1 -t "$DRAIN" c; do
        seq+=$c
    done
    REPLY_SEQ=$seq
}

restore_tty() { stty "$SAVED_TTY" 2>/dev/null; }

SAVED_TTY=$(stty -g)
trap 'restore_tty; echo; exit 130' INT
trap restore_tty EXIT
stty -echo -icanon min 1 time 0 2>/dev/null

if [[ "${1:-}" == "--show" ]]; then
    printf 'Press keys to see their bytes (Ctrl-C to quit).\n\n'
    while read_seq; do
        printf '  %-14s  %s\n' "$(caret "$REPLY_SEQ")" "$(hexdump_str "$REPLY_SEQ")"
    done
    exit 0
fi

# Guided checklist: label, key to press, expected bytes (xterm form).
ESC=$'\e'
TESTS=(
    "F1|F1|${ESC}OP"
    "Shift+F1|Shift-F1|${ESC}[1;2P"
    "F4|F4|${ESC}OS"
    "Shift+F4|Shift-F4|${ESC}[1;2S"
    "F5|F5|${ESC}[15~"
    "Shift+F5|Shift-F5|${ESC}[15;2~"
    "Ctrl+F5|Control-F5|${ESC}[15;5~"
    "F6|F6|${ESC}[17~"
    "Shift+F6|Shift-F6|${ESC}[17;2~"
)

pass=0
fail=0
printf 'Guided validation. Press the key named for each line.\n'
printf '(press Return to skip a key you cannot produce)\n\n'
printf '  %-10s  %-14s  %-14s  %s\n' "KEY" "GOT" "EXPECTED" "RESULT"
printf '  %-10s  %-14s  %-14s  %s\n' "---" "---" "--------" "------"

for entry in "${TESTS[@]}"; do
    IFS='|' read -r label press expected <<< "$entry"
    printf '  %-10s  ' "$label"
    read_seq
    if [[ "$REPLY_SEQ" == $'\n' || "$REPLY_SEQ" == $'\r' ]]; then
        printf '%-14s  %-14s  %s\n' "(skipped)" "$(caret "$expected")" "SKIP"
        continue
    fi
    got_caret=$(caret "$REPLY_SEQ")
    exp_caret=$(caret "$expected")
    if [[ "$REPLY_SEQ" == "$expected" ]]; then
        printf '%-14s  %-14s  PASS\n' "$got_caret" "$exp_caret"
        (( pass++ ))
    else
        printf '%-14s  %-14s  FAIL\n' "$got_caret" "$exp_caret"
        (( fail++ ))
    fi
done

echo
printf 'Summary: %d passed, %d failed.\n' "$pass" "$fail"
if (( fail > 0 )); then
    printf 'A FAIL for a modified key in a -CC session (with the plain session\n'
    printf 'passing) is the issue 10717 symptom.\n'
    exit 1
fi
