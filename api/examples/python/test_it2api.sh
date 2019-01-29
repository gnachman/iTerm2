#!/bin/bash
PYTHON=python3.7
PYTHONPATH=`pwd`/../../library/python/iterm2/iterm2

function expect_contains() {
    echo -n "$1: "
    if [[ $3 == *"$2"* ]]; then
        echo OK
    else
        die "$2 not in $3"
    fi
}

function expect_nothing() {
    echo "$1: OK"
}

function die() {
    echo "$1" 1>& 2
    exit 1
}

set -x

OUTPUT=$($PYTHON it2api create-tab)
REGEX='id=([^ ]*) .([0-9]*) x ([0-9]*)'
[[ $OUTPUT =~ $REGEX ]]
FIRST_SESSION_ID="${BASH_REMATCH[1]}"
WIDTH="${BASH_REMATCH[2]}"

expect_contains "list-sessions" "$FIRST_SESSION_ID" "$($PYTHON it2api list-sessions)"
expect_contains "show-hierarchy" "$FIRST_SESSION_ID" "$($PYTHON it2api show-hierarchy)"

TEXT="qwerty"
$PYTHON it2api send-text $FIRST_SESSION_ID "$TEXT" || die "send-text failed"
expect_contains "get-buffer" "$TEXT" "$($PYTHON it2api get-buffer $FIRST_SESSION_ID)"

OUTPUT=$($PYTHON it2api split-pane "$FIRST_SESSION_ID")
REGEX='id=([^ ]*) .([0-9]*) x ([0-9]*)'
[[ $OUTPUT =~ $REGEX ]]
SESSION_ID="${BASH_REMATCH[1]}"
WIDTH="${BASH_REMATCH[2]}"

expect_contains "split-pane" "Session" "$OUTPUT"
expect_contains "get-prompt" "working_directory: \"$HOME\"" "$($PYTHON it2api get-prompt $FIRST_SESSION_ID)" 
expect_nothing "set-profile-property" "$($PYTHON it2api set-profile-property $SESSION_ID ansi_0_color '(255,255,255,255 sRGB)')"
expect_contains "get-profile-property" "(255,255,255,255 ColorSpace.SRGB)" "$($PYTHON it2api get-profile-property $SESSION_ID ansi_0_color)"

expect_nothing "inject" "$($PYTHON it2api inject $SESSION_ID 'Press x')"
expect_contains "read" 'chars=x' "$($PYTHON it2api read $SESSION_ID char)"

OUTPUT=$($PYTHON it2api show-hierarchy | grep "Window" | tail -1)
REGEX='id=(pty-[^ ]*)'
[[ $OUTPUT =~ $REGEX ]]
WINDOW_ID="${BASH_REMATCH[1]}"

expect_nothing "set-window-property" "$($PYTHON it2api set-window-property $WINDOW_ID frame 0,0,600,600)"
expect_contains "get-window-property" "0,0,600,600" "$($PYTHON it2api get-window-property $WINDOW_ID frame)"

expect_nothing "activate" "$($PYTHON it2api activate session $FIRST_SESSION_ID)"
expect_contains "activate+show-focus" "$FIRST_SESSION_ID" "$($PYTHON it2api show-focus)"

# Can't really test this since I can't deactivate it
expect_nothing "activate-app" "$($PYTHON it2api activate session $FIRST_SESSION_ID)"

expect_nothing set-variable "$($PYTHON it2api set-variable --session $SESSION_ID user.foo 123)"
expect_contains get-variable 123 "$($PYTHON it2api get-variable --session $SESSION_ID user.foo)"
expect_contains list-variables user.foo "$($PYTHON it2api list-variables --session $SESSION_ID)"

expect_nothing "initialize preset" "$($PYTHON it2api set-color-preset Default "Dark Background")"
expect_contains set-preset-initialized 0,0,0,255 "$($PYTHON it2api get-profile-property $FIRST_SESSION_ID background_color)"
expect_nothing "initialize preset" "$($PYTHON it2api set-color-preset Default "Light Background")"
expect_contains set-preset-initialized 255,255,255,255 "$($PYTHON it2api get-profile-property $FIRST_SESSION_ID background_color)"

$PYTHON it2api send-text $FIRST_SESSION_ID "cd /etc"
expect_contains monitor-variable /etc "$($PYTHON it2api monitor-variable --session $FIRST_SESSION_ID session.path)"

# Missing tests:
# saved-arrangement
# list-profiles
