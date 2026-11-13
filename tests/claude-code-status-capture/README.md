# Capturing what Claude Code tells iTerm2

iTerm2 shows Claude Code’s status from two sources and combines them
(`sources/ClaudeCode/ClaudeCodeStatusOverlay.swift`): the Program Status Protocol reports Claude
Code sends itself (OSC 7501, `app=claude-code`), and the facts its hook
(`it2 handle-agent-hook`) stores. The replay tests in
`ModernTests/ClaudeCodeHookAndReportsTests.swift` are built from recordings of both, taken with
the scripts here on Claude Code 2.1.322. When Claude Code changes what or when it reports, record
again and compare.

Run this on a test VM, in a tab of the build under test, not on your own Mac’s Claude Code setup.

## Recording

Copy this directory to the VM (below, `SCRIPTS` is where it landed). The logs go in
`~/cc-status-capture`, or in `$CC_CAPTURE_DIR` if you set it for both `rec` and `timeline.py`.

    mkdir -p ~/cc-status-capture

1. Hook payloads. Make a settings file whose hooks run `SCRIPTS/rec` first and then the build’s
   hook command (`<app>/Contents/Resources/utilities/it2 handle-agent-hook`) for every event
   iTerm2 installs (Notification, PermissionRequest, PostToolUse, PreToolUse, SessionEnd,
   SessionStart, Stop, StopFailure, SubagentStop, UserPromptSubmit), and start Claude Code with
   `--setting-sources project,local --settings FILE` so the installed hooks do not also run.
2. Reports. Start Claude Code under the relay:

       python3 -I SCRIPTS/relay.py ~/cc-status-capture/osc7501.log claude --setting-sources project,local --settings FILE

   The log shows the probe (`7501 ?`), iTerm2’s reply, and every report.
3. Run a scenario, then merge the two logs from its start time:

       python3 -I SCRIPTS/timeline.py 17:33:30

## Scenarios

The tests replay these five:

- A background agent (Agent tool, `run_in_background`) that works for a while.
- A background shell (Bash, `run_in_background`).
- A background agent that pauses on background shells of its own.
- A tool call that needs permission, approved.
- Esc during a tool call.

Also worth recording, though not replayed: `/compact` and `/exit` (the clear Claude Code sends as
it exits ends its reporting, and the tests cover that directly), and all of the above inside a
tmux Integration pane and over ssh. On 2.1.322 Claude Code sent the probe inside tmux, got
iTerm2’s reply, and still sent no reports, so the hook is the only source there.
`SCRIPTS/probe.py` sends the probe by hand and prints the reply.

## What to compare

- Whether the root record still says working for a whole background-agent wait, and done as soon
  as a turn ends with a background shell running.
- Whether done carries a message (`msg=`).
- The order and spacing of each report and the hook event for the same moment. The replay tests
  reorder events less than 300 ms apart.
- Whether reports now appear inside tmux.
