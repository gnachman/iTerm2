# Claude Code Integration Research

Research notes from studying jc (a Rust/gpui app that wraps Claude Code) to inform
building similar functionality in iTerm2.

## How jc Communicates with Claude Code

The communication is asymmetric:

- **jc -> Claude Code**: PTY stdin (keystrokes and bracketed-paste text)
- **Claude Code -> jc**: HTTP hooks (Claude Code POSTs JSON to a localhost server)

There is no bidirectional API. jc is essentially a terminal emulator (using
alacritty's VTE) with a hook server bolted on.

### Sending Input

Claude Code runs as a PTY subprocess via the `portable_pty` crate. All input
goes through the PTY writer:

- **Keystrokes**: Converted to terminal escape sequences and written directly.
- **Text paste**: Wrapped in bracketed paste mode (`\x1b[200~...\x1b[201~`),
  with ESC bytes stripped to prevent escape injection. Enter (`\r`) is sent
  after a 200ms delay on a background thread to give Claude Code time to
  process the paste.
- **Commands**: `/copy`, prompt text, etc. are pasted the same way.

### Receiving State

jc installs hooks into `.claude/settings.local.json` pointing at a localhost
HTTP server (using `tiny_http`, ~190 lines). Claude Code fires POST requests
when its state changes. The hook server parses the JSON body and sends events
through a flume channel to the main app.

Hook event types jc uses:

| Hook | Meaning |
|------|---------|
| `UserPromptSubmit` | User submitted a prompt -- Claude is about to work |
| `Stop` | Claude finished normally |
| `StopFailure` | API error during execution |
| `Notification` (idle_prompt) | Claude finished, waiting for new input |
| `Notification` (permission_prompt) | Permission dialog shown |
| `PermissionRequest` | Tool permission dialog appeared |
| `SessionEnd` | Session ended (used to detect `/clear`) |
| `SessionStart` | Session started (paired with SessionEnd for `/clear`) |

Not all hook types support `"type": "http"`. `SessionEnd` and `SessionStart`
only support `"type": "command"`, so jc works around this by using command hooks
that pipe stdin through `curl` back to its own HTTP server.

## State Tracking

Core state in jc's `SessionState`:

- `busy: bool` -- true while Claude is actively working
- `has_ever_been_busy: bool` -- true once Claude has worked at least once
- `pending_events: HashSet<PendingEvent>` -- tracks permission prompts, API errors, terminal bells

Transitions:
- `PromptSubmit` -> `busy = true`
- `Stop` / `IdlePrompt` / `PermissionPrompt` / `StopFailure` -> `busy = false`

## Diff Discovery

jc does NOT rely on hooks to learn which files changed. It runs
`git2::Repository::diff_tree_to_workdir_with_index()` to compare HEAD against
the working tree. Diffs are refreshed:

- Every 2 seconds when the window is active (working-tree diffs are always
  considered stale since `.git/index` mtime doesn't reflect unstaged edits)
- Immediately when a hook event fires (Stop, StopFailure, etc.)

Each file diff gets a checksum. A `reviewed` hashmap tracks which files the user
has marked as reviewed. If the diff content changes, the reviewed state is
invalidated.

## Tricky Edge Cases jc Solved

1. **`/clear` two-event correlation**: `/clear` fires `SessionEnd` then
   `SessionStart` as separate hooks. jc stashes the `SessionEnd` with a
   10-second expiry and pairs it with the subsequent `SessionStart` by
   project path.

2. **UUID bootstrapping**: Fresh `claude` sessions start with `uuid = None`.
   The UUID is discovered on the first hook event. jc does a two-pass match:
   first by UUID across all projects, then falls back to assigning to a
   pending `uuid=None` session in the matching project.

3. **200ms paste delay**: Enter is sent on a background thread after 200ms to
   let the PTY buffer process pasted content. There's no "paste complete"
   acknowledgment.

4. **Escape sanitization**: `write_text()` strips `\x1b` from pasted content
   to prevent premature termination of bracketed paste mode.

5. **L2 problem suppression**: "Unsent WAIT" notifications are suppressed when
   Claude is busy or higher-priority problems exist, to avoid noise.

6. **L0 cross-session "home"**: Permission prompts can require jumping to a
   different session. The system saves a "home" session on the first jump and
   returns after all L0 problems are resolved.

7. **Multi-instance hook collision**: Hook uninstall removes ALL `/jc-hook/`
   URLs, which would break a second instance's hooks.

8. **File watcher self-write suppression**: An `AtomicBool` flag suppresses
   filesystem watcher events for 200ms after jc itself writes a file.

9. **`usize::MAX` sentinel**: The refresh channel uses `usize::MAX` as a
   "wake up and re-evaluate" signal distinct from project-index-targeted
   refreshes.

10. **Clipboard polling for `/copy`**: After sending `/copy` to Claude Code's
    PTY, jc polls the system clipboard every 200ms for up to 3 seconds waiting
    for it to change. No API exists to extract Claude's last response directly.

## jc UI Structure

jc is a multi-pane IDE built on gpui (Zed's GPU-accelerated UI framework).
Default layout is three resizable side-by-side panes, each of which can be:

- **Claude Terminal** -- Claude Code's TUI in a full terminal emulator
- **General Terminal** -- a regular shell
- **Code Viewer** -- syntax-highlighted editor (tree-sitter) for files and `/copy` replies
- **Git Diff** -- diff view with reviewed/unreviewed tracking
- **TODO Editor** -- per-project TODO.md with session management
- **Global TODO** -- cross-project todo list

Claude Code's output is shown directly in the terminal pane. The `/copy`
feature extracts the last reply into the code viewer as a convenience.

## Implications for iTerm2

### Hook transport

Command hooks work for all event types; HTTP hooks don't (SessionEnd/SessionStart
are command-only). For iTerm2, command hooks are the natural choice since they
can invoke `it2` to talk to iTerm2 over its existing API endpoint (raw protobuf).
This avoids running an HTTP server entirely.

The hook command would be something like:
```
it2 claude-hook --session-id $SESSION_ID
```
with JSON on stdin, and `it2` forwards it to iTerm2 via the API socket.

### What iTerm2 needs from hooks

For parity with jc's functionality:

- **UserPromptSubmit**: Mark session as busy (spinner, status indicator)
- **Stop / Notification(idle_prompt)**: Mark session as idle
- **StopFailure**: Show error indicator
- **Notification(permission_prompt) / PermissionRequest**: Show attention badge
- **SessionEnd / SessionStart**: Track `/clear` for session identity

Other events (PreToolUse, PostToolUse, SubagentStart, etc.) could power
richer UI like tool activity indicators or progress tracking.

### Existing iTerm2 mechanisms that could help

- **Triggers**: Regex on terminal output, useful for detecting patterns Claude
  Code renders (progress bars, prompts). Complement hooks for things not
  covered by the hook protocol.
- **Badges/marks**: Visual indicators for session state.
- **Python API / `it2`**: IPC channel for hook commands to report events.

### Swift types

`ClaudeCodeHookEvent.swift` was written to `it2cli/Sources/it2/` with Codable
structs covering all 25 hook event types from the official spec at
https://code.claude.com/docs/en/hooks.
