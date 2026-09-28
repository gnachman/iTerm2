#!/bin/bash
# Manual test for a tab status that expires when the progress protocol says
# the operation it was scoped to has ended.
#
# Run this inside a session of a Development build of iTerm2 and watch the
# tab's status dot and text (the Session Status toolbelt tool shows the detail
# too). Everything here is plain escape sequences, so it exercises the OSC
# 21337 path without needing it2 or the API.
#
# The same states are what cc-status now asks for over it2:
#   it2 session set-status --session "$ID" --status working --dot-color '#ff9500' \
#       --expires-on progress-end --then-status idle --then-dot-color '#00d75f'

set -u

# OSC 21337: tab status. Payload is key=value pairs joined by semicolons.
status() { printf '\033]21337;%s\007' "$1"; }
# OSC 9;4: ConEmu progress. 3 = indeterminate (running), 0 = stopped.
progress() { printf '\033]9;4;%s;\007' "$1"; }

pause() {
    echo "    $1"
    sleep "${2:-3}"
}

echo
echo "1. A working status scoped to the operation, then the operation ends."
status 'status=working;status-color=#ff9500;indicator=#ff9500;detail=doing the thing;expires-on=progress-end;then-status=idle;then-status-color=#888888;then-indicator=#00d75f;then-detail='
pause "armed: tab should read working (orange). Nothing has started yet." 2
progress 3
pause "running: still working." 3
progress 0
pause "stopped: within a few seconds the tab should turn idle (green)." 5

echo
echo "2. A newer status supersedes the expiration."
status 'status=working;indicator=#ff9500;expires-on=progress-end;then-status=idle;then-indicator=#00d75f'
progress 3
pause "running: working." 2
status 'status=waiting;indicator=#5f87ff'
pause "the program spoke again: waiting (blue), and no longer expiring." 2
progress 0
pause "stopped: the tab must STAY waiting. Going idle here is a bug." 5

echo
echo "3. The program's own word wins the race at the end of an operation."
status 'status=working;indicator=#ff9500;expires-on=progress-end;then-status=idle;then-indicator=#00d75f'
progress 3
pause "running: working." 2
progress 0
status 'status=working;indicator=#ff9500;detail=the program spoke'
pause "a status set inside the head start must survive: still working, with" 5
pause "that detail. Flipping to idle here is a bug." 2

echo
echo "4. A stop with nothing armed does nothing."
status 'status=waiting;indicator=#5f87ff'
progress 3
progress 0
pause "no expiration was armed, so the tab must stay waiting." 5

echo
echo "5. An error state ends the operation too."
status 'status=working;indicator=#ff9500;expires-on=progress-end;then-status=idle;then-indicator=#00d75f'
progress 3
pause "running: working." 2
printf '\033]9;4;2;\007'
pause "reported failure: the tab should go idle within a few seconds," 4
pause "because a program that reports an error may never send a stop." 2

echo
echo "6. A paused state does NOT end the operation."
status 'status=working;indicator=#ff9500;expires-on=progress-end;then-status=idle;then-indicator=#00d75f'
progress 3
pause "running: working." 2
printf '\033]9;4;4;50\007'
pause "paused: the tab must STAY working. Going idle here is a bug." 5
progress 0
pause "stopped: now it should go idle." 4

echo
echo "Not covered here: an expiration is also held while the program has"
echo "reported outstanding background tasks, and fires when that count"
echo "reaches zero. The OSC payload has no background-task field, so that"
echo "path is exercised by it2 --background-tasks and by the unit tests in"
echo "ModernTests/TabStatusControllerTests.swift."

echo
echo "Done. Clearing."
status 'status=;status-color=;indicator=;detail='
