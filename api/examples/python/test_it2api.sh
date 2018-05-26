#!/bin/bash
PYTHON=~/Library/ApplicationSupport/iTerm2/iterm2env/versions/3.6.5/bin/python3.6

function expect_contains() {
    echo -n "$1: "
    echo -n "$3" | grep "$2" > /dev/null && echo "OK" || die "$2 not in $3"
}

function expect_nothing() {
    echo "$1: OK"
}

function die() {
    echo "$1" 1>& 2
    exit 1
}

OUTPUT=$($PYTHON it2api create-tab)
REGEX='id=([^ ]*) .([0-9]*) x ([0-9]*)'
[[ $OUTPUT =~ $REGEX ]]
FIRST_SESSION_ID="${BASH_REMATCH[1]}"
WIDTH="${BASH_REMATCH[2]}"
HEIGHT="${BASH_REMATCH[3]}"

expect_contains "list-sessions" "$FIRST_SESSION_ID" "$($PYTHON it2api list-sessions)"
expect_contains "show-hierarchy" "$FIRST_SESSION_ID" "$($PYTHON it2api show-hierarchy)"

TEXT="qwerty"
$PYTHON it2api send-text $FIRST_SESSION_ID "$TEXT" || die "send-text failed"
expect_contains "get-buffer" "$TEXT" "$($PYTHON it2api get-buffer $FIRST_SESSION_ID $HEIGHT)"

OUTPUT=$($PYTHON it2api split-pane "$FIRST_SESSION_ID")
REGEX='id=([^ ]*) .([0-9]*) x ([0-9]*)'
[[ $OUTPUT =~ $REGEX ]]
SESSION_ID="${BASH_REMATCH[1]}"
WIDTH="${BASH_REMATCH[2]}"
HEIGHT="${BASH_REMATCH[3]}"

expect_contains "split-pane" "Session" "$OUTPUT"
expect_contains "get-prompt" "working_directory: \"$HOME\"" "$($PYTHON it2api get-prompt $FIRST_SESSION_ID)" 
expect_nothing "set-profile-property" "$($PYTHON it2api set-profile-property $SESSION_ID ansi_0_color '(255,255,255,255 sRGB)')"
expect_contains "get-profile-property" "(255,255,255,255 sRGB)" "$($PYTHON it2api get-profile-property $SESSION_ID ansi_0_color)"

expect_nothing "inject" "$($PYTHON it2api inject $SESSION_ID 'Press x')"
expect_contains "read" 'characters: "x"' "$($PYTHON it2api read $SESSION_ID char)"

OUTPUT=$($PYTHON it2api show-hierarchy | grep "Window" | tail -1)
REGEX='id=(pty-[^ ]*)'
[[ $OUTPUT =~ $REGEX ]]
WINDOW_ID="${BASH_REMATCH[1]}"

expect_nothing "set-window-property" "$($PYTHON it2api set-window-property $WINDOW_ID frame 0,0,800,800)"
expect_contains "get-window-property" "0,0,800,800" "$($PYTHON it2api get-window-property $WINDOW_ID frame)"

expect_nothing "activate" "$($PYTHON it2api activate session $FIRST_SESSION_ID)"
expect_contains "activate+show-focus" "$FIRST_SESSION_ID" "$($PYTHON it2api show-focus)"

# Can't really test this since I can't deactivate it
expect_nothing "activate-app" "$($PYTHON it2api activate session $FIRST_SESSION_ID)"

expect_nothing set-variable "$($PYTHON it2api set-variable $SESSION_ID user.foo 123)"
expect_contains get-variable 123 "$($PYTHON it2api get-variable $SESSION_ID user.foo)"
expect_contains list-variables user.foo "$($PYTHON it2api list-variables $SESSION_ID)"

# Missing tests:
# saved-arrangement
# list-profiles

