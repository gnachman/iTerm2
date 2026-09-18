#!/bin/bash
# Manual repro for issue 13058: OSC 6;1;bg;*;default restores the wrong tab color.
#
# The reset is supposed to put the tab color back the way the profile had it.
# The suspicion is that when the profile has separate light/dark colors turned on
# but has no Tab Color (Light) / Tab Color (Dark) keys, the first escape-sequence
# write invents those keys, and the second write records the just-written escape
# color as the pre-escape baseline. The reset then restores that instead.
#
# Run with no arguments for the guided walkthrough. Other modes:
#
#   tab-color-reset-repro.sh setup SUITE  put the profile in the state under test
#   tab-color-reset-repro.sh set R G B    emit just the three component writes
#   tab-color-reset-repro.sh reset        emit just the reset
#   tab-color-reset-repro.sh show         print the sequences without sending them

set -u

esc() {
    printf '\033]6;1;bg;%s\a' "$1"
}

set_color() {
    # Three separate control sequences, which is how every wrapper script does it.
    # Each one is a separate profile write inside iTerm2, which is what the bug
    # depends on.
    esc "red;brightness;$1"
    esc "green;brightness;$2"
    esc "blue;brightness;$3"
}

reset_color() {
    esc '*;default'
}

show() {
    cat <<'EOF'
Set the tab color (three writes, red then green then blue):

    printf '\033]6;1;bg;red;brightness;255\a'
    printf '\033]6;1;bg;green;brightness;128\a'
    printf '\033]6;1;bg;blue;brightness;0\a'

Reset it to the profile value:

    printf '\033]6;1;bg;*;default\a'
EOF
}

pause() {
    printf '\n%s\n' "$1"
    printf 'Press return to continue. '
    read -r _
}

# Rewrite the first profile of a suite so it has a tab color on the base key only,
# which is what a profile carried over from 3.6 looks like. iTerm2 writes its prefs
# from memory when it quits, so editing them under a running instance accomplishes
# nothing. Refuse rather than silently do nothing.
setup() {
    local suite="$1"
    if pgrep -fl -- "-suite $suite" | grep -q "iTerm2"; then
        echo "An iTerm2 instance is using -suite $suite. Quit it first." >&2
        exit 1
    fi
    python3 - "$suite" <<'PY'
import plistlib, subprocess, sys

suite = sys.argv[1]
raw = subprocess.run(['defaults', 'export', suite, '-'], capture_output=True).stdout
d = plistlib.loads(raw)
b = d['New Bookmarks'][0]

for key in ['Tab Color (Light)', 'Tab Color (Dark)',
            'Use Tab Color (Light)', 'Use Tab Color (Dark)']:
    b.pop(key, None)

b['Use Separate Colors for Light and Dark Mode'] = True
b['Use Tab Color'] = True
b.setdefault('Tab Color', {'Red Component': 0.0, 'Green Component': 0.8,
                           'Blue Component': 0.2, 'Alpha Component': 1.0,
                           'Color Space': 'sRGB'})

path = '/tmp/%s-tabcolor-setup.plist' % suite
open(path, 'wb').write(plistlib.dumps(d))
subprocess.run(['defaults', 'import', suite, path], check=True)

print('profile %s is now:' % b.get('Name'))
for k in sorted(b):
    if 'Tab Color' in k or 'Separate' in k:
        print('   ', k, '=', b[k])
PY
    echo
    echo "Now relaunch and run this script in a NEW window. Session restoration"
    echo "carries a divorced session profile forward, stale keys included."
}

case "${1:-}" in
    setup)
        if [ $# -lt 2 ]; then
            echo "usage: $0 setup SUITE" >&2
            exit 1
        fi
        setup "$2"
        exit 0
        ;;
    set)
        set_color "${2:-255}" "${3:-128}" "${4:-0}"
        exit 0
        ;;
    reset)
        reset_color
        exit 0
        ;;
    show)
        show
        exit 0
        ;;
    "")
        ;;
    *)
        echo "unknown mode: $1" >&2
        echo "usage: $0 [setup SUITE | set R G B | reset | show]" >&2
        exit 1
        ;;
esac

cat <<'EOF'
Issue 13058 walkthrough.

Preconditions for the profile this session is using:

  Use Separate Colors for Light and Dark Mode = true   (the shipped default)
  Use Tab Color                               = true
  Tab Color                                   = some obvious color
  Tab Color (Light) / (Dark)                  = ABSENT
  Use Tab Color (Light) / (Dark)              = ABSENT

The last two lines are the whole point, and they are also the part that is easy
to get wrong. Setting a tab color from Settings or from the View menu writes all
three variants, and re-checking the separate light/dark box copies the base color
into both variants, so neither of those leaves the profile in the state above.
A profile carried over from 3.6 with a tab color already set does have that shape.

To get there, quit the instance and run:

  tests/tab-color-reset-repro.sh setup SUITE

then relaunch and run this in a NEW window (session restoration carries a divorced
session profile forward, stale keys included).

To check the profile, with the app quit, where SUITE is your -suite argument:

  python3 - <<'PY'
  import plistlib, subprocess
  d = plistlib.loads(subprocess.run(['defaults','export','SUITE','-'],
                                    capture_output=True).stdout)
  for b in d['New Bookmarks']:
      print(b.get('Name'), {k: v for k, v in b.items()
                            if 'Tab Color' in k or 'Separate' in k})
  PY

EOF

pause "Step 1. Look at the tab. It should be showing the profile tab color."

set_color 255 128 0
pause "Step 2. Sent the three component writes. The tab should be orange now."

reset_color
pause "Step 3. Sent the reset. Expected: back to the profile tab color.
Bug: the tab has no color at all, or it has a color the profile never had."

cat <<'EOF'

If the tab looks right, the profile probably still has the (Light)/(Dark) keys,
so nothing could be polluted. Check it as described above and try again.

Either way, the stored values are worth a look, since the damage can be invisible
when the enable bit for the active appearance ends up off. Turn on debug logging
before running this (iTerm2 > Toggle Debug Logging, or launch with
StartDebugLoggingAutomatically set for the suite), toggle it off afterward, then:

  grep -n "setSessionSpecificProfilevalues" -A 25 /tmp/debuglog.txt | tail -40

The last write is the one from the reset. Tab Color should be the profile value.
If Tab Color (Light) and Tab Color (Dark) hold the color that existed partway
through step 2, rather than being removed, that is the bug.

EOF
