#!/bin/bash
# Manual test for the Program Status Protocol (OSC 7501).
# Watch the tab's status subtitle, indicator dot, and progress bar, and the
# Session Status tool. Spec: https://www.superlogical.com/rex/docs/build/program-status

report() {
    printf '\e]7501;%s\e\\' "$1"
}

b64() {
    printf '%s' "$1" | base64 | tr -d '\n'
}

# Each step waits for Return, and pressing a key in this session tells
# iTerm2 the user has seen any done or error status, which turns it idle.
# So a done or error shown at one step is idle by the time the next step's
# reports arrive. That is expected, not a bug.
step() {
    echo
    echo "== $1"
    read -r -p "Press return to continue... "
}

# Feature detection: iTerm2 answers with the same body. The reply ends in
# ESC \, so read up to the backslash.
printf '\e]7501;?\e\\'
if IFS= read -r -s -t 2 -d '\\' reply; then
    echo "Feature detection reply: $(printf '%s\\' "$reply" | cat -v)"
else
    echo "No reply to feature detection: OSC 7501 is unsupported"
fi

report "state=working:app=brew:progress=30:msg=$(b64 'Installing updates')"
step "Expect: working, “Installing updates”, bar at 30%"

report "state=blocked:kind=auth:app=brew:msg=$(b64 'Password required')"
step "Expect: waiting, “Password required”, bar paused (yellow) at 30%"

report "state=working:app=deploy:msg=$(b64 'Deploying v2.4.1')"
report "state=working:id=us-east:title=$(b64 'US East'):progress=40:msg=$(b64 'Pushing image')"
report "state=blocked:kind=permission:id=eu-west:title=$(b64 'EU West')"
step "Expect: waiting, “EU West: Waiting for approval” (most urgent record wins)"

report "state=clear:id=eu-west"
step "Expect: working, “US East: Pushing image”, bar at 40%"

report "state=error:id=us-east:title=$(b64 'US East'):msg=$(b64 'Push failed')"
step "Expect: error, “US East: Push failed”, bar red"

report "state=clear"
report "state=done:app=deploy:msg=$(b64 'Deployed to 3 regions')"
echo
echo "Expect: done, “Deployed to 3 regions”, no bar."
echo "It should survive the next shell prompt, and turn idle (keeping its"
echo "message) when you press a key."
