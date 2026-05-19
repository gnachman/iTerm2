#!/bin/bash
#
# Interactive test for issue 12870: OSC color overrides should persist across
# macOS Light/Dark appearance switches AND across toggles of the
# "Use separate colors for Light Mode and Dark Mode" profile setting.
#
# Also exercises OSC 110/111 reset and XTPUSHCOLORS/XTPOPCOLORS round-trip.
#
# Run inside an iTerm2 session you can afford to mess with: this script
# mutates fg/bg/cursor/selection/palette colors and relies on you to
# eyeball the result between steps.

set -u

ESC=$'\033'
BEL=$'\007'
ST=$ESC'\'

# Color helpers
ORANGE='ff/80/00'   # OSC 10/11 - very visible
MAGENTA='ff/00/ff'  # OSC 12 (cursor)
GREEN='00/cc/00'    # OSC 4 (palette index)
CYAN='00/cc/cc'     # OSC 17 (selection bg)

# Pretty print
say() { printf '\n\033[1;33m=== %s ===\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
prompt() {
    printf '\n\033[1;36m? %s\033[0m\n' "$*"
    printf '  Press Enter to continue, or Ctrl-C to abort: '
    read -r _
}

ask_yn() {
    local q="$1" ans
    while :; do
        printf '\n\033[1;36m? %s (y/n): \033[0m' "$q"
        read -r ans
        case "$ans" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
        esac
    done
}

osc() {
    # osc <code> <payload>
    printf '%s]%s;%s%s' "$ESC" "$1" "$2" "$BEL"
}

push_colors()  { printf '%s[#P' "$ESC"; }
pop_colors()   { printf '%s[#Q' "$ESC"; }

reset_fg()    { printf '%s]110%s' "$ESC" "$BEL"; }
reset_bg()    { printf '%s]111%s' "$ESC" "$BEL"; }
reset_cursor(){ printf '%s]112%s' "$ESC" "$BEL"; }
reset_palette(){ printf '%s]104;%s%s' "$ESC" "$1" "$BEL"; }

# ------------------------------------------------------------------------
say "iTerm2 OSC color persistence test (issue 12870)"
note "This session's fg/bg/cursor/selection/palette will be changed."
note "Have System Settings -> Appearance and Profiles -> Colors handy."
note "Make sure your current profile has BOTH light and dark color presets"
note "configured (any contrasting colors will do)."
prompt "Ready to begin"

# ------------------------------------------------------------------------
say "1. OSC 11 (background) survives appearance switch"
note "Setting background to orange via OSC 11..."
osc 11 "rgb:$ORANGE"
note "The window background should now be orange."
prompt "Now toggle System Settings -> Appearance between Light and Dark"
if ask_yn "Did the orange background persist through the appearance toggle?"; then
    note "PASS"
else
    note "FAIL - this is the core bug from issue 12870"
fi

# ------------------------------------------------------------------------
say "2. OSC 11 survives separate-colors toggle"
note "Background should still be orange from step 1."
prompt "Open Edit Session (Cmd-I) -> Colors and toggle 'Use separate colors for Light Mode and Dark Mode'"
if ask_yn "Did the orange background persist through the separate-colors toggle?"; then
    note "PASS"
else
    note "FAIL"
fi
prompt "Toggle it back to the state you started in"

# ------------------------------------------------------------------------
say "3. OSC 111 reset clears the override completely"
note "Resetting background via OSC 111..."
reset_bg
note "Background should be back to the profile's value (NOT orange)."
prompt "Toggle System Settings -> Appearance once more"
if ask_yn "Did the background follow the profile's appearance-matched preset (no leftover orange)?"; then
    note "PASS"
else
    note "FAIL - reset is leaking the OSC value into one of the variants"
fi

# ------------------------------------------------------------------------
say "4. OSC 10 (foreground) survives appearance switch"
note "Setting foreground to orange via OSC 10..."
osc 10 "rgb:$ORANGE"
note "Text should now render in orange."
prompt "Toggle System Settings -> Appearance"
if ask_yn "Did the orange foreground persist?"; then
    note "PASS"
else
    note "FAIL"
fi
note "Resetting foreground..."
reset_fg

# ------------------------------------------------------------------------
say "5. OSC 12 (cursor) survives appearance switch"
note "Setting cursor color to magenta..."
osc 12 "rgb:$MAGENTA"
note "Cursor should be magenta. Click in this terminal so it's the focused cursor."
prompt "Toggle System Settings -> Appearance"
if ask_yn "Did the magenta cursor persist?"; then
    note "PASS"
else
    note "FAIL"
fi
note "Resetting cursor..."
reset_cursor

# ------------------------------------------------------------------------
say "6. OSC 17 (selection bg) survives appearance switch"
note "Setting selection background to cyan..."
osc 17 "rgb:$CYAN"
note "Now select some text in this terminal with the mouse to see the highlight."
echo "  ---- select this text to see the selection color ----"
prompt "Selection should be cyan. Now toggle System Settings -> Appearance"
if ask_yn "Did the cyan selection bg persist? (Re-select if needed.)"; then
    note "PASS"
else
    note "FAIL"
fi
note "Resetting selection..."
printf '%s]117%s' "$ESC" "$BEL"

# ------------------------------------------------------------------------
say "7. OSC 4 (ANSI palette) survives appearance switch"
note "Overriding ANSI 1 (red) -> green via OSC 4..."
osc 4 "1;rgb:$GREEN"
printf '\033[31mThis line uses ANSI 1 (should look green, not red).\033[0m\n'
prompt "Toggle System Settings -> Appearance"
printf '\033[31mThis line still uses ANSI 1 (should STILL look green).\033[0m\n'
if ask_yn "Did the ANSI 1 override persist?"; then
    note "PASS"
else
    note "FAIL"
fi
note "Resetting palette index 1..."
reset_palette 1
printf '\033[31mThis line should be back to your profile red.\033[0m\n'

# ------------------------------------------------------------------------
say "8. OSC 1337 SetColors=bg survives appearance switch"
note "Setting bg via iTerm's proprietary SetColors..."
printf '%s]1337;SetColors=bg=00aaff%s' "$ESC" "$BEL"
note "Background should be blue."
prompt "Toggle System Settings -> Appearance"
if ask_yn "Did the blue bg persist?"; then
    note "PASS"
else
    note "FAIL"
fi
note "Resetting bg..."
reset_bg

# ------------------------------------------------------------------------
say "9. XTPUSHCOLORS / XTPOPCOLORS round-trip survives appearance switch"
note "Pushing current colors to slot 0, then setting bg=orange..."
push_colors
osc 11 "rgb:$ORANGE"
note "Background is orange. The pre-push colors are saved."
prompt "Toggle System Settings -> Appearance (orange should persist as in step 1)"
note "Now popping colors back from slot 0..."
pop_colors
note "Background should be back to whatever it was BEFORE the push (not orange,"
note "and not the OSC 110/111 reset value unless that's what it was pre-push)."
prompt "Toggle System Settings -> Appearance"
if ask_yn "Did the popped background persist through the toggle?"; then
    note "PASS"
else
    note "FAIL - PopColors is dropping the appearance-switch fix"
fi

# ------------------------------------------------------------------------
say "10. PopColors does NOT clobber match-highlight color"
note "Cmd-F in this session and search for some text so the match highlight shows."
note "Note the highlight color."
prompt "Now we'll push, change bg, pop"
push_colors
osc 11 "rgb:$ORANGE"
note "Background is orange. Searching..."
prompt "Search again (Cmd-F) and confirm the match highlight color is unchanged"
pop_colors
note "After PopColors, search once more."
if ask_yn "Is the match-highlight color STILL the same as before push/pop?"; then
    note "PASS - PopColors no longer corrupts match color (fixed in this diff)"
else
    note "FAIL"
fi

# ------------------------------------------------------------------------
say "Done"
note "If anything failed, re-run with the build from this branch and compare."
note "To fully restore your profile colors, you can use Profiles -> Reset"
note "(or just quit and reopen the session)."
