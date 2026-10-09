#!/bin/bash
# Manual test for the paused-indeterminate progress state. Run it in a
# background tab so the tab's indicator is visible (the active tab hides it),
# and watch both the thin bar at the top of the session and the tab.

step() {
    echo
    echo "== $1"
    read -r -p "Press return to continue... "
}

printf '\e]9;4;3\a'
step "OSC 9;4;3: scrolling band in the session, spinner in the tab"

printf '\e]9;4;4\a'
step "OSC 9;4;4: still yellow band centered in the session, yellow pause symbol in the tab"

printf '\e]9;4;3\a'
step "OSC 9;4;3: scrolling and spinning again"

printf '\e]7501;state=blocked:kind=permission\e\\'
step "OSC 7501 blocked: paused again"

printf '\e]7501;state=working\e\\'
step "OSC 7501 working: scrolling and spinning again"

printf '\e]9;4;0\a'
printf '\e]7501;state=clear\e\\'
echo "Cleared."
