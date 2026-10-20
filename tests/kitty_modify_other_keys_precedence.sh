#!/bin/bash
# Checks whether xterm's modifyOtherKeys request (CSI > 4 ; 2 m) or other
# XTMODKEYS requests clear kitty keyboard protocol flags. Issue 13138.
#
# Run it in kitty, then in iTerm2, and compare the summaries.
#
# Each scenario resets key reporting, sends some sequences, then:
#   1. Queries the kitty flags with CSI ? u. This needs no input from you.
#   2. Asks you to press Escape and then Ctrl+I, and shows the bytes received.
#
# What the key bytes mean:
#   Escape  ^[[27u          kitty protocol active (disambiguate)
#   Escape  ^[              legacy encoding
#   Ctrl+I  ^[[105;5u       kitty protocol active
#   Ctrl+I  ^[[27;5;105~    modifyOtherKeys=2 active
#   Ctrl+I  ^I              legacy encoding (a tab)

ESC=$'\033'
SAVED_STTY=$(stty -g)

reset_modes() {
    # Pop everything, zero the flags, and reset modifyOtherKeys and modifyCursorKeys.
    printf '%s' "${ESC}[<99u${ESC}[=0;1u${ESC}[>4n${ESC}[>1n"
}

cleanup() {
    reset_modes
    stty "$SAVED_STTY"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Prints bytes the way cat -vt does (tab shows as ^I).
visible() {
    printf '%s' "$1" | cat -vt
}

# Reads whatever arrives within about one second and prints it. The tty stays
# in non-canonical, no-echo mode for the whole run so a reply that arrives
# before we start reading is neither echoed nor stuck in the line buffer.
read_with_timeout() {
    local result="" chunk
    stty min 0 time 10
    while :; do
        chunk=$(dd bs=64 count=1 2>/dev/null; printf x)
        chunk=${chunk%x}
        [ -z "$chunk" ] && break
        result+=$chunk
        case "$result" in *u) break ;; esac
        stty min 0 time 2
    done
    printf '%s' "$result"
}

# Discards anything already waiting, such as a late reply.
drain_input() {
    stty min 0 time 0
    while [ "$(dd bs=64 count=1 2>/dev/null; printf x)" != x ]; do
        :
    done
}

# Waits for one keypress and prints its bytes.
read_key() {
    local result
    stty min 1 time 2
    result=$(dd bs=64 count=1 2>/dev/null; printf x)
    printf '%s' "${result%x}"
}

query_flags() {
    # Write to the tty: stdout is captured by the caller.
    printf '%s' "${ESC}[?u" > /dev/tty
    local reply
    reply=$(read_with_timeout)
    if [[ "$reply" =~ \[\?([0-9]+)u ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf 'no reply (%s)' "$(visible "$reply")"
    fi
}

SUMMARY=()

run_scenario() {
    local name=$1 sequences=$2 shown=$3
    echo
    echo "=== $name"
    echo "    sends: $shown"
    reset_modes
    printf '%s' "$sequences"
    local flags
    flags=$(query_flags)
    echo "    kitty flags (CSI ? u): $flags"

    drain_input
    echo -n "    Press Escape: "
    local esc_bytes
    esc_bytes=$(visible "$(read_key)")
    echo "$esc_bytes"

    echo -n "    Press Ctrl+I: "
    local ctrl_i_bytes
    ctrl_i_bytes=$(visible "$(read_key)")
    echo "$ctrl_i_bytes"

    reset_modes
    SUMMARY+=("$(printf '%-44s flags=%-4s Esc=%-10s Ctrl+I=%s' "$name" "$flags" "$esc_bytes" "$ctrl_i_bytes")")
}

# Non-canonical and no echo, but keep output processing and Ctrl+C.
stty -icanon -echo

echo "Terminal: ${TERM_PROGRAM:-unknown} ${TERM_PROGRAM_VERSION:-} ${KITTY_WINDOW_ID:+(kitty window $KITTY_WINDOW_ID)}"
echo "You will be asked to press Escape, then Ctrl+I, once per scenario."

run_scenario "1. baseline: push 1" \
    "${ESC}[>1u" 'CSI > 1 u'
run_scenario "2. push 1, then modifyOtherKeys=2" \
    "${ESC}[>1u${ESC}[>4;2m" 'CSI > 1 u, CSI > 4 ; 2 m'
run_scenario "3. modifyOtherKeys=2, then push 1" \
    "${ESC}[>4;2m${ESC}[>1u" 'CSI > 4 ; 2 m, CSI > 1 u'
run_scenario "4. set 1, then modifyOtherKeys=2" \
    "${ESC}[=1;1u${ESC}[>4;2m" 'CSI = 1 ; 1 u, CSI > 4 ; 2 m'
run_scenario "5. push 1, then modifyCursorKeys=2" \
    "${ESC}[>1u${ESC}[>1;2m" 'CSI > 1 u, CSI > 1 ; 2 m'
run_scenario "6. push 1, then reset modifyOtherKeys" \
    "${ESC}[>1u${ESC}[>4n" 'CSI > 1 u, CSI > 4 n'
run_scenario "7. push 1, modifyOtherKeys=2, then pop" \
    "${ESC}[>1u${ESC}[>4;2m${ESC}[<1u" 'CSI > 1 u, CSI > 4 ; 2 m, CSI < 1 u'

echo
echo "=== Summary"
for line in "${SUMMARY[@]}"; do
    echo "$line"
done
