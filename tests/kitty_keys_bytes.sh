#!/bin/bash
# Print each key report a terminal sends under the Kitty keyboard protocol.
#
# Run in any terminal (Kitty, iTerm2, ...) to compare what they send:
#     bash tests/kitty_keys_bytes.sh [flags]
#
# flags defaults to 15:
#   1 disambiguate | 2 report-event-types | 4 report-alternate-keys
#   | 8 report-all-keys-as-escape-codes | 16 report-associated-text
#
# Press q (or Ctrl-C) to quit. Used for issue 13136 (Caps Lock release
# reported as CSI 1:3 u).

flags=${1:-15}
saved=$(stty -g)

cleanup() {
    printf '\033[<u'
    stty "$saved"
}
trap cleanup EXIT

stty raw -echo
printf '\033[>%su' "$flags"
printf 'Pushed Kitty flags %s. Press keys; q or Ctrl-C quits.\r\n' "$flags"

show() {
    local s=${1//$'\033'/\\e}
    printf '%s\r\n' "$s"
}

while IFS= read -r -s -n 1 -d '' c; do
    if [[ $c == $'\033' ]]; then
        seq=$c
        IFS= read -r -s -n 1 -d '' c
        seq+=$c
        if [[ $c == '[' || $c == 'O' ]]; then
            # Read until the final byte of the CSI/SS3 sequence.
            while IFS= read -r -s -n 1 -d '' c; do
                seq+=$c
                [[ $c == [A-Za-z~] ]] && break
            done
        fi
    else
        seq=$c
    fi
    show "$seq"
    case $seq in
        q|$'\003'|$'\033[113u'|$'\033[113;'*u|$'\033[99;5u'|$'\033[99;5:1u')
            break
            ;;
    esac
done
