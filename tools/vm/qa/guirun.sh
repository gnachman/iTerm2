#!/bin/bash
# Runs on the test VM, invoked over ssh by tools/vm/qa.sh. Runs a command in the logged-in user's
# GUI session as a one-shot LaunchAgent, waits for it to finish, and prints its output.
#
# Some things don't work from an ssh session even with the right permissions, such as taking a
# screenshot. A program run this way is its own "responsible process" for privacy permissions,
# so it needs its own grant (e.g. Screen Recording for vmctl).
#
# Usage: guirun.sh /absolute/path/to/program [ARG]...

label="com.iterm2.vmqa.guirun.$$"
out="/tmp/$label.out"
plist="/tmp/$label.plist"
args=""
for a in "$@"; do
    args+="<string>$(printf %s "$a" | sed 's/&/\&amp;/g;s/</\&lt;/g')</string>"
done
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>StandardOutPath</key><string>$out</string>
<key>StandardErrorPath</key><string>$out</string>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
: > "$out"
launchctl bootstrap "gui/$(id -u)" "$plist"
# Wait up to 60 seconds for the job to exit.
for _ in $(seq 1 600); do
    launchctl print "gui/$(id -u)/$label" 2>/dev/null | grep -q 'state = running' || break
    sleep 0.1
done
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
cat "$out"
rm -f "$out" "$plist"
