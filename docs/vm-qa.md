# Hands-on QA on a test VM

Unit tests can't tell you whether focus lands where a user expects, whether a panel appears in the
right place, or whether a drag feels right. For changes like that, drive a real build on a test VM
with synthetic mouse and keyboard events, read the accessibility tree, and take screenshots.
`tools/vm/qa.sh` does all of this over ssh, so nothing happens on the developer's Mac.

Never use accessibility APIs, synthetic events, or screenshots on the developer's own Mac. Only on
a VM they've given you.

## Before you start

Ask the developer which VM to use, every time. There are only a few and they decide who gets
which. Don't pick one yourself, don't fall back to a default, and don't assume a VM from an
earlier session is still yours. Every `qa.sh` command takes `--host VM` as its first argument.

The VM must already be provisioned for tests (`tools/vm/provision_test_vm.sh`, which only the
developer runs), and the developer's GUI session must be logged in.

Privacy permissions are granted by the developer at the VM's screen, once per VM. In System
Settings > Privacy & Security (on macOS 27, input control is listed under “Device Control and
Data Access” rather than Accessibility):

| What | Needs | Grant it to |
| --- | --- | --- |
| Pointer, keyboard, reading focus, menus, window frames | Accessibility | `/usr/libexec/sshd-keygen-wrapper` (ssh sessions) |
| Screenshots | Screen Recording | `~/iterm2-vm-test/qa/vmctl` |

`tools/vm/qa.sh --host VM setup` prints which of these are missing. To make vmctl show up in the Screen
Recording list, run `tools/vm/qa.sh --host VM sh '~/iterm2-vm-test/qa/guirun.sh ~/iterm2-vm-test/qa/vmctl request'`.
vmctl is signed with the local Apple Development identity, so the grant survives rebuilding it.
Ask the developer for missing grants with exact paths, and do everything that doesn't need them
first.

Features that need a plugin (inline AI chat needs iTermAI.app, browser panes need
iTermBrowserPlugin.app) need it installed in the VM's /Applications. Ask the developer.

## The loop

With the VM the developer gave you (`vm2` here):

```
q() { tools/vm/qa.sh --host vm2 "$@"; }
q setup                  # once per session: install vmctl, check permissions
q build                  # build this working tree on the VM
q build-baseline         # optional: build origin/master to compare against
q sh defaults write qa FocusFollowsMouse -bool true
q launch                 # or: launch baseline
q ctl click 600 500
q ctl type "echo PANE_A"
q ctl key 36             # Return
q f                      # what has focus?
q shot                   # screenshot to tmp/vm-qa/shot.png; read it
q clean                  # when done
```

`tools/vm/qa.sh --host VM` with no command lists every command. The vmctl commands are listed at the top
of `tools/vm/qa/vmctl.swift`.

Write the QA plan before testing: numbered cases with steps and expected results. Track results
case by case, and note how each was tested when it wasn't the way a user would do it.

## Builds and settings

- The candidate runs with settings suite `qa` and the baseline with `qa-baseline`, so neither
  touches the other's settings or the test runner's. A new suite starts with default settings.
- Write settings only while the app is quit (`qa.sh quit`); a running app overwrites them. Then
  `launch`. Keys are the ones in `iTermPreferences.m`. Advanced settings use the name in
  `iTermAdvancedSettingsModel.m`, capitalized (`StealKeyFocus`).
- Profiles live in the suite's “New Bookmarks” array. Edit them with `qa.sh profiles SUITE ...`
  after the suite's first launch, e.g. `qa.sh profiles qa add Web 'Custom Command="Browser"'
  'Initial URL="https://example.com"'`, then open it from Shell > Split Vertically… by typing
  its name.
- `launch` turns off window restoration, quits leftover session servers, hides other apps, and
  gives the app one window at 100,80 sized 1400x800 (`--frame` changes it).
- `build-baseline [REF]` builds a git ref in a separate VM checkout. The first one is a full
  build. Use it to decide whether a finding is a regression: run the same steps on both builds.
- A test run on the same VM (`tools/run_tests_vm.sh`) quits every iTerm2 it built, including
  yours. Don't run tests on the VM you're doing hands-on QA on; ask the developer for another
  VM or wait.

## Driving the app

- Coordinates are global screen points, top-left origin. `shot` prints how to turn image pixels
  back into points. Get this right before clicking on something you saw in a screenshot: the
  image is scaled, so its pixels are not points.
- `ctl move` glides through intermediate points like a real pointer, so tracking areas fire.
  `ctl down`, `ctl drag`, `ctl up` make drags.
- `ctl type` types ASCII with key codes for a US layout. Common key codes: Return 36, Tab 48,
  Escape 53, Delete 51, arrows 123 (left) 124 (right) 125 (down) 126 (up), and with `cmd`: D 2,
  F 3, N 45, T 17, W 13, ] 30.
- System shortcuts such as Control-arrow (Spaces) and Control-up (Mission Control) need
  `ctl chord KEYCODE`, which sends a real Control key press.
- `qa.sh menu Shell "Split Vertically…"` presses menu items by title. Use the real `…`.
- Any argument that is exactly `PID` is replaced with the app's process id: `ctl wins PID`,
  `ctl setframe PID f 100 80 800 600`.
- To make iTerm2 inactive, activate another app: `ctl activate com.apple.finder`.
- `ctl flick DY` sends a trackpad scroll with momentum. It's synthetic, so treat it as weaker
  evidence than a real trackpad and say so in results.

## Checking results

- Echo a marker like `PANE_A` in each pane. `qa.sh f` shows the focused element and the last
  `PANE_` marker in its text, so you can tell panes apart without a screenshot.
- The accessibility tree can lag or be stale (web views, the AI chat input). Confirm anything
  that matters by typing a unique word and checking where it appeared, in a screenshot or with
  `f`.
- `ctl watchfocus PID 40` samples focus for two seconds to catch flicker.
- `qa.sh log` prints the app's stdout and stderr. For temporary diagnostics, add `NSFuckingLog`
  lines, rebuild, and read them there. Remove them before committing.
- Debug logging through the app's menu may be blocked by the agent's permission checker; the log
  above is the reliable route.

## Cleaning up

`qa.sh clean` quits the apps and deletes the QA settings suites, the baseline checkout and its
build, and the tools on the VM. It doesn't undo changes made through the UI: remove extra Spaces
in Mission Control (`ctl chord 126`, hover the Space, click its close button) and say what's
left over when you report.
