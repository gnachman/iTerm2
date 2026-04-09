# it2 CLI Test Plan

Run these from a terminal inside iTerm2 with the Python API enabled.
Replace `it2` with the path to the binary if it's not in your PATH.

## Prerequisites

```
export PATH=/path/to/it2cli/.build/debug:$PATH
```

Ensure iTerm2 has: Settings > General > Magic > Enable Python API checked.

---

## Session Commands

### session list

```
it2 session list
```

Should print one line per session: `<UUID>\t<title>`. Verify the count matches
the number of open sessions across all windows and tabs.

### session split (horizontal)

```
it2 session split
```

Should print `Created new pane: <UUID>` and a new horizontal split appears in
the active session.

### session split (vertical)

```
it2 session split -v
```

Should print `Created new pane: <UUID>` and a new vertical split appears.

### session split (targeted)

```
SESSION=$(it2 session list | head -1 | cut -f1)
it2 session split -v -s "$SESSION"
```

Should split the specific session, not the active one.

### session split (with profile)

```
PROFILE=$(it2 profile list | head -1 | cut -f2)
it2 session split -p "$PROFILE"
```

Should split using the named profile.

### session run

```
SESSION=$(it2 session split -v | awk '{print $NF}')
it2 session run -s "$SESSION" "echo hello from it2"
```

Should execute the echo command in the newly created pane. Verify "hello from
it2" appears in that pane.

### session send

```
it2 session send -s "$SESSION" "typed without enter"
```

Should type the text into the pane but NOT press enter. The text should appear
at the prompt without executing.

### session send --all

```
it2 session send -a "broadcast test"
```

Should type "broadcast test" into every session.

### session close

```
SESSION=$(it2 session split | awk '{print $NF}')
it2 session close -f -s "$SESSION"
```

Should print `Session closed` and the pane disappears.

### session close (no force)

```
SESSION=$(it2 session split | awk '{print $NF}')
it2 session close -s "$SESSION"
```

Should show a confirmation prompt in iTerm2 (unless "confirm before closing" is
disabled).

### session restart

```
SESSION=$(it2 session list | head -1 | cut -f1)
it2 session restart -s "$SESSION"
```

Should print `Session restarted`. The session's shell restarts.

### session focus

```
SESSION=$(it2 session list | tail -1 | cut -f1)
it2 session focus "$SESSION"
```

Should print `Focused session: <UUID>` and that session becomes the active pane,
its tab is selected, and its window comes to front.

### session read

```
it2 session read
```

Should print the visible screen contents of the active session.

### session read (with line count)

```
it2 session read -l 5
```

Should print only the last 5 lines of the screen.

### session clear

```
it2 session clear
```

Should clear the active session's screen (sends Ctrl+L).

### session capture

```
it2 session capture -o /tmp/it2-capture.txt
```

Should print `Screen captured to: /tmp/it2-capture.txt`. Verify the file
contains the screen contents:

```
cat /tmp/it2-capture.txt
rm /tmp/it2-capture.txt
```

### session set-name

```
SESSION=$(it2 session list | head -1 | cut -f1)
it2 session set-name -s "$SESSION" "Test Name"
```

Should print `Session name set to: Test Name`. Verify the tab/session title
updated in iTerm2.

### session set-color

```
SESSION=$(it2 session list | head -1 | cut -f1)
it2 session set-color -s "$SESSION" "#FF0000"
```

Should print `Tab color set to #FF0000`. The session's tab should turn red.

Reset it:

```
it2 session set-color -s "$SESSION" "#000000"
```

### session get-var

```
it2 session get-var session.name
```

Should print the JSON-encoded value of the session name variable.

### session set-var

```
SESSION=$(it2 session list | head -1 | cut -f1)
it2 session set-var user.testVar '"hello"' -s "$SESSION"
```

Should print `Set user.testVar = "hello"`. Verify:

```
it2 session get-var user.testVar -s "$SESSION"
```

Should print `"hello"`.

---

## Window Commands

### window new

```
it2 window new
```

Should print `Created new window: <window_id>` and a new window appears.

### window new (with profile)

```
it2 window new -p Default
```

Should create a new window using the Default profile.

### window list

```
it2 window list
```

Should print one line per window: `<window_id>\t<N> tabs`.

### window focus

```
WINDOW=$(it2 window list | head -1 | cut -f1)
it2 window focus "$WINDOW"
```

Should print `Focused window: <id>` and bring that window to front.

### window move

```
WINDOW=$(it2 window list | head -1 | cut -f1)
it2 window move 100 100 "$WINDOW"
```

Should print `Moved window to (100, 100)`. The window moves on screen.

### window resize

```
WINDOW=$(it2 window list | head -1 | cut -f1)
it2 window resize 800 600 "$WINDOW"
```

Should print `Resized window to 800x600`.

### window fullscreen

```
WINDOW=$(it2 window list | head -1 | cut -f1)
it2 window fullscreen on "$WINDOW"
```

Window enters fullscreen. Then:

```
it2 window fullscreen off "$WINDOW"
```

Window exits fullscreen.

```
it2 window fullscreen toggle
```

Toggles current window fullscreen state.

### window close

```
it2 window new
WINDOW=$(it2 window list | tail -1 | cut -f1)
it2 window close -f "$WINDOW"
```

Should print `Window closed`.

### window arrange save

```
it2 window arrange save test-arrangement
```

Should print `Saved arrangement: test-arrangement`.

### window arrange list

```
it2 window arrange list
```

Should include `test-arrangement` in the output.

### window arrange restore

```
it2 window arrange restore test-arrangement
```

Should print `Restored arrangement: test-arrangement` and windows/tabs are
restored.

---

## Tab Commands

### tab new

```
it2 tab new
```

Should print `Created new tab: <tab_id>` and a new tab appears in the current
window.

### tab new (with profile)

```
it2 tab new -p Default
```

### tab list

```
it2 tab list
```

Should print one line per tab with tab ID, window ID, index, and session count.

### tab list (filtered by window)

```
WINDOW=$(it2 window list | head -1 | cut -f1)
it2 tab list -w "$WINDOW"
```

Should only list tabs in that window.

### tab select

```
TAB=$(it2 tab list | head -1 | cut -f1)
it2 tab select "$TAB"
```

Should print `Selected tab: <id>` and that tab becomes active.

### tab close

```
it2 tab new
TAB=$(it2 tab list | tail -1 | cut -f1)
it2 tab close -f "$TAB"
```

Should print `Tab closed`.

### tab next / prev

```
it2 tab next
```

Should print `Switched to tab <N>` and advance to the next tab.

```
it2 tab prev
```

Should go back.

### tab goto

```
it2 tab goto 0
```

Should select the first tab.

### tab move

```
it2 tab new
it2 tab move
```

Should print `Moved tab to new window` and the current tab detaches into a new
window.

---

## Profile Commands

### profile list

```
it2 profile list
```

Should print one line per profile: `<GUID>\t<name>`.

### profile show

```
it2 profile show Default
```

Should print profile properties (key: value pairs).

### profile apply

```
PROFILE=$(it2 profile list | head -1 | cut -f2)
it2 profile apply "$PROFILE"
```

Should print `Applied profile '<name>' to session`.

### profile set

```
it2 profile set Default badge-text '"test badge"'
```

Should print `Set badge-text = "test badge" for profile 'Default'`. Note: this
modifies the actual profile, not just the session.

---

## App Commands

### app activate

```
it2 app activate
```

Should print `iTerm2 activated` and bring iTerm2 to front.

### app hide

```
it2 app hide
```

Should print `iTerm2 hidden` and hide the app. Click the dock icon to bring it
back.

### app version

```
it2 app version
```

Should print `iTerm2 version: <version string>`.

### app theme (get)

```
it2 app theme
```

Should print `Current theme: <theme name>`.

### app theme (set)

```
it2 app theme dark
```

Should print `Theme set to: dark`. Restore:

```
it2 app theme automatic
```

### app get-focus

```
it2 app get-focus
```

Should print the current window, tab, and session IDs without `Optional(...)` wrappers.

### app broadcast on

```
it2 session split -v
it2 app broadcast on
```

Should print `Broadcasting enabled for current tab`. Type in one pane and it
appears in both.

### app broadcast off

```
it2 app broadcast off
```

Should print `Broadcasting disabled`.

### app broadcast add

```
S1=$(it2 session list | sed -n '1p' | cut -f1)
S2=$(it2 session list | sed -n '2p' | cut -f1)
it2 app broadcast add "$S1" "$S2"
```

Should print `Created broadcast group with 2 sessions`.

### app quit

**Warning: this will quit iTerm2.**

```
it2 app quit
```

Should print `iTerm2 quit command sent`.

---

## Monitor Commands

These are long-running. Press Ctrl+C to stop each one.

### monitor output

```
it2 monitor output
```

Should print current screen contents once and exit.

### monitor output (follow)

```
it2 monitor output -f &
MONITOR_PID=$!
# In another pane, type some commands
kill $MONITOR_PID
```

Should continuously print screen updates as they happen.

### monitor output (with pattern)

```
it2 monitor output -p "ERROR"
```

Should only print lines matching "ERROR".

### monitor keystroke

```
it2 monitor keystroke
```

Type some keys. Each keystroke should appear as `Keystroke: <char>`. Ctrl+C to
stop.

### monitor variable

```
it2 monitor variable session.name
```

Change the session name (via Preferences or `it2 session set-name`). Should
print `Changed to: <new value>`. Ctrl+C to stop.

### monitor variable (app-level)

```
it2 monitor variable effectiveTheme --app-level
```

Change the theme. Should print the new value. Ctrl+C to stop.

### monitor prompt

```
it2 monitor prompt
```

Run commands in the monitored session (requires shell integration). Should print:
- `New prompt detected` when a prompt appears
- `Command started: <cmd>` when a command begins
- `Command finished (exit status: <N>)` when it ends

Ctrl+C to stop.

### monitor activity

```
it2 monitor activity -a
```

Switch between sessions. Should print `Session active: <name>` and
`Session idle: <name>` as sessions gain/lose focus. Ctrl+C to stop.

---

## Auth Commands

### auth cookie (reusable)

```
it2 auth cookie
```

An announcement should appear in the session offering duration options (24
Hours, Forever, Always Allow All Apps, Deny). Choose "24 Hours". Should print
`ITERM2_COOKIE=<cookie> ITERM2_KEY=<key>`.

Verify it works:

```
export $(it2 auth cookie)
time it2 session list > /dev/null
```

Should complete in ~10ms (not ~140ms).

Verify reuse:

```
time it2 session list > /dev/null
time it2 session list > /dev/null
```

All should be fast.

### auth cookie (single-use)

```
it2 auth cookie --single-use
```

Should print cookie without showing an announcement.

---

## Top-Level Shortcuts

### ls

```
it2 ls
```

Same output as `it2 session list`.

### send

```
it2 send "hello"
```

Same as `it2 session send "hello"`.

### run

```
it2 run "echo shortcut test"
```

Same as `it2 session run "echo shortcut test"`.

### split / vsplit

```
it2 split
it2 vsplit
```

Same as `it2 session split` and `it2 session split -v`.

### clear

```
it2 clear
```

Same as `it2 session clear`.

### new

```
it2 new
```

Same as `it2 window new`.

### newtab

```
it2 newtab
```

Same as `it2 tab new`.

---

## Config Commands

### config-path

```
it2 config-path
```

Should print the path to `~/.it2rc.yaml` and whether it exists.

### config-reload

Create a test config:

```
cat > ~/.it2rc.yaml << 'EOF'
profiles:
  test:
    - command: echo "loaded from config"
aliases:
  hello: session run "echo hello from alias"
EOF
```

```
it2 config-reload
```

Should print `Configuration reloaded` and list the loaded profiles and aliases.

### load

```
it2 load test
```

Should print `Loading profile: test` and execute the commands defined in the
profile.

### alias

```
it2 alias hello
```

Should print `Running alias 'hello': session run "echo hello from alias"` and
execute it.

Clean up:

```
rm ~/.it2rc.yaml
```

---

## Environment Variables

### IT2_APP_PATH

```
IT2_APP_PATH="/Applications/iTerm.app" it2 session list
```

Should target the specified iTerm2 instance for AppleScript auth.

### IT2_SUITE

```
IT2_SUITE="iTerm2" it2 session list
```

Should connect to `~/Library/Application Support/iTerm2/private/socket`.
A different value should connect to a different socket path.

### ITERM2_COOKIE / ITERM2_KEY

```
export $(it2 auth cookie --single-use)
it2 session list
unset ITERM2_COOKIE ITERM2_KEY
```

First `session list` should use the cookie from env (fast). After unset, should
fall back to AppleScript.

---

## Error Handling

### Bad session ID

```
it2 session run -s "nonexistent-uuid" "echo test"
```

Should print an error and exit non-zero.

### API disabled

Disable Python API in Settings, then:

```
it2 session list
```

Should print a connection or auth error.

### Bad color format

```
it2 session set-color -s "$(it2 session list | head -1 | cut -f1)" "notacolor"
```

Should print an error about invalid color format.
