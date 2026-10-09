#!/usr/bin/env python3
"""End-to-end tests for cc-status.

Feeds recorded hook payloads (tests/fixtures/<agent>/*.json, from Claude Code
2.1.201 and Codex CLI 0.154, paths scrubbed) through the built binary and
checks the exact it2 calls it makes. cc-status looks for it2 next to its own
executable, so the binary is copied beside a fake it2 that logs each call and
keeps the state the real one keeps: the displayed status, the background-task
count and the turn flag.

    swift build -c release && python3 tests/run.py
"""

import fcntl
import json
import os
import pty
import shutil
import subprocess
import sys
import tempfile
import termios
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "tests", "fixtures")
SESSION = "TEST-SESSION"
ARG_SEPARATOR = "\x1f"

FAKE_IT2 = r'''#!/bin/sh
# Fake it2: log argv (one line per call, args separated by \x1f) and keep the
# state cc-status reads back: the displayed status, the background-task count
# and the turn flag.
printf '%s\037' "$@" >> "$CC_STATUS_TEST_LOG"
printf '\n' >> "$CC_STATUS_TEST_LOG"
# Stands in for the hook being killed on its timeout, without any sleeping:
# once this many calls have been logged, kill cc-status where it stands.
if [ -n "$CC_STATUS_TEST_KILL_AFTER" ] &&
   [ "$(wc -l < "$CC_STATUS_TEST_LOG")" -ge "$CC_STATUS_TEST_KILL_AFTER" ]; then
    kill -9 "$PPID"
fi
state="$CC_STATUS_TEST_STATE"
print_status() {
    status=null
    if [ -f "$state/status" ]; then
        status="\"$(cat "$state/status")\""
    fi
    turn=null
    if [ -f "$state/turn-open" ]; then
        turn=$(cat "$state/turn-open")
    fi
    count=$(cat "$state/background-tasks" 2>/dev/null || echo 0)
    printf '{"status":%s,"detail":null,"background_tasks":%s,"turn_open":%s}\n' \
        "$status" "$count" "$turn"
}
case "$1 $2" in
    "set-status "*)
        status_given=""
        new_status=""
        new_count=""
        delta=""
        new_turn=""
        if_turn=""
        if_count=""
        want_json=""
        # Options arrive as --name=value, except an empty value, which comes
        # as two arguments (see optionArgs in Addressing.swift); the address,
        # the quiet flag and the expiration are logged but change nothing here.
        while [ $# -gt 0 ]; do
            case "$1" in
                --status=*) status_given=1; new_status="${1#*=}" ;;
                --status) status_given=1; new_status="$2"; shift ;;
                --background-tasks=*) new_count="${1#*=}" ;;
                --background-tasks-delta=*) delta="${1#*=}" ;;
                --turn-open=*) new_turn="${1#*=}" ;;
                --if-turn-open=*) if_turn="${1#*=}" ;;
                --if-background-tasks=*) if_count="${1#*=}" ;;
                --json) want_json=1 ;;
            esac
            shift
        done
        # Preconditions are checked against the state as it stands and a
        # failed one drops the whole update. The real one does this atomically.
        apply=1
        if [ -n "$if_turn" ] && [ "$(cat "$state/turn-open" 2>/dev/null || echo unknown)" != "$if_turn" ]; then
            apply=""
        fi
        if [ -n "$if_count" ] && [ "$(cat "$state/background-tasks" 2>/dev/null || echo 0)" != "$if_count" ]; then
            apply=""
        fi
        if [ -n "$apply" ]; then
            if [ -n "$status_given" ]; then
                printf '%s\n' "$new_status" > "$state/status"
                # Stands in for a sub-agent finishing while this write is in
                # flight: the count cc-status read a moment ago is now stale.
                if [ -n "$CC_STATUS_TEST_FINISH_ON_STATUS_WRITE" ]; then
                    printf '0\n' > "$state/background-tasks"
                fi
            fi
            if [ -n "$new_count" ]; then
                printf '%s\n' "$new_count" > "$state/background-tasks"
            fi
            if [ -n "$delta" ]; then
                # Applied where the count lives and clamped at zero. The real
                # one does this atomically.
                current=$(cat "$state/background-tasks" 2>/dev/null || echo 0)
                new=$((current + delta))
                if [ "$new" -lt 0 ]; then
                    new=0
                fi
                printf '%s\n' "$new" > "$state/background-tasks"
            fi
            if [ -n "$new_turn" ]; then
                printf '%s\n' "$new_turn" > "$state/turn-open"
            fi
        fi
        if [ -n "$want_json" ]; then
            # The status as it stands once the update above has landed.
            print_status
            # Stands in for a prompt submitted between this answer and the
            # caller's next write: its hook reopened the turn and wrote
            # "working", which that write must not cover.
            if [ -n "$CC_STATUS_TEST_PROMPT_AFTER_JSON" ]; then
                printf 'working\n' > "$state/status"
                printf 'true\n' > "$state/turn-open"
            fi
        else
            echo "Session status updated."
        fi
        ;;
    "session get-background-tasks")
        cat "$state/background-tasks" 2>/dev/null || echo 0
        ;;
    "session get-status")
        print_status
        ;;
    *)
        echo "fake it2: unexpected command: $*" >&2
        exit 1
        ;;
esac
'''

WORKING = ["--status=working", "--dot-color=#ff9500", "--text-color=#ff9500"]
WAITING = ["--status=waiting", "--dot-color=#5f87ff", "--text-color=#5f87ff"]
IDLE = ["--status=idle", "--dot-color=#00d75f", "--text-color=#888888"]
DONE = ["--status=done", "--dot-color=#00d75f", "--text-color=#00d75f"]
ERROR = ["--status=error", "--dot-color=#ff3b30", "--text-color=#ff3b30"]
# What a Claude Code status scoped to the turn asks iTerm2 to do when the
# session's progress protocol reports the turn ended. Never sent for Codex,
# whose ring cc-status draws itself.
EXPIRES = ["--expires-on=progress-end", "--then-status=idle", "--then-dot-color=#00d75f",
           "--then-text-color=#888888", "--then-detail", ""]


# Every call carries the pane address the way cc-status phrases it. The
# per-tool-call events also ask it2 for silence about an unresolved pane; the
# two session boundaries do not, so a persistent problem is reported once at
# each end of the session (see It2Runner).
ADDRESS = ["--session=" + SESSION]
QUIET = ["--quiet-if-unresolved"]


def set_status(*args, boundary=False):
    return ["set-status", *ADDRESS, *([] if boundary else QUIET), *args]


# An option with a value goes as one argument; an empty value goes as two,
# which is the one form ArgumentParser accepts for it.
def detail(text):
    return ["--detail", ""] if text == "" else ["--detail=" + text]


def get_background_tasks():
    return ["session", "get-background-tasks", *ADDRESS, *QUIET]


def get_status():
    return ["session", "get-status", *ADDRESS, *QUIET]


# A change to the count asks for the status that results, in the same call.
def background_tasks_delta(value):
    return ["set-status", *ADDRESS, "--background-tasks-delta=" + value, "--json", *QUIET]


TURN_OPEN = ["--turn-open=true"]
TURN_CLOSED = ["--turn-open=false"]
# A turn closing with work still counted asks for the status as of the close.
TURN_CLOSED_COUNTING = TURN_CLOSED + ["--json"]
# A turn ending decided from a status read a round trip earlier: it carries what it
# assumed, so iTerm2 drops it if a prompt reopened the turn in between, and it
# asks for the result so the progress ring can wait for it.
IF_FINISHED = ["--if-turn-open=false", "--if-background-tasks=0", "--json"]

# A step that, instead of running a hook, wipes the displayed status the way
# iTerm2 does when the visible fields are cleared but the parked count and
# turn flag live on.
FORGET_STATUS = ("forget the displayed status",)

# A step that, instead of running a hook, does what iTerm2 does when the user
# types in a session showing a finished or failed turn: it becomes idle.
USER_TYPED = ("user typed in the session",)


# A step that checks what the fake session displays, for scenarios whose point
# is a write that must not land.
def expect_status(status):
    return ("expect displayed status", status)

# OSC 9;4 progress ring the Codex path writes to the agent's terminal.
RING = {"working": b"\x1b]9;4;3\x07", "waiting": b"\x1b]9;4;0\x07", "idle": b"\x1b]9;4;0\x07",
        "done": b"\x1b]9;4;0\x07", "error": b"\x1b]9;4;0\x07"}


def expected_ring(fixture, expected, extra):
    if not fixture.startswith("codex/"):
        return b""  # Claude Code draws its own ring; the hook must stay quiet.
    ring = b""
    for call in expected:
        status = [arg[len("--status="):] for arg in call if arg.startswith("--status=")]
        if call[:1] != ["set-status"] or not status:
            continue
        if "--if-turn-open=false" in call and "CC_STATUS_TEST_PROMPT_AFTER_JSON" in extra:
            continue  # Dropped by iTerm2, so the ring must not change either.
        ring += RING[status[0]]
    return ring


# Runs the hook the way Codex 0.155+ does (openai/codex#43876): the parent holds
# the terminal, the hook is started with setsid and has no controlling terminal.
DETACHED = """
import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    os.execv(sys.argv[1], sys.argv[1:])
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
"""


class Terminal:
    """Reads the pty master continuously; an unread pty blocks the session
    leader's exit until its output is drained."""

    def __init__(self, master):
        self.data = b""
        self.thread = threading.Thread(target=self._read, args=(master,), daemon=True)
        self.thread.start()

    def _read(self, master):
        while True:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                return
            if not chunk:
                return
            self.data += chunk


# (fixture, expected it2 calls in order[, env]). A scenario runs its steps
# against one fake session, so state stored by an earlier step is visible to
# later ones. The optional third element adds environment for that one step.
SCENARIOS = {
    "codex: plain turn": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/PreToolUse-Bash", [set_status(*WORKING, *detail(""))]),
        ("codex/PostToolUse-Bash", [set_status(*WORKING, *detail(""))]),
        ("codex/Stop-hello", [get_background_tasks(),
                              set_status(*DONE, *detail("HELLO"), *TURN_CLOSED)]),
    ],
    "codex: detached sub-agent outlives the parent turn": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/PreToolUse-spawn_agent", [set_status(*WORKING, *detail(""))]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        # Parent goes idle while the child runs: stay working, and learn from
        # the same write whether the child finished during it.
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("1 background task running"),
                                           *TURN_CLOSED_COUNTING)]),
        # Child finishes; nothing else will fire, so SubagentStop reports idle.
        ("codex/SubagentStop", [background_tasks_delta("-1"),
                                set_status(*DONE, *detail("DONE"), *IF_FINISHED)]),
    ],
    "codex: sub-agent finishes while the parent's Stop is being written": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        # Stop read the count as 1, but by the time its status lands the child
        # has finished. The child saw the turn still open and stayed quiet, so
        # nothing else will ever clear the "working"; the count that comes
        # back with the write catches it.
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("1 background task running"),
                                           *TURN_CLOSED_COUNTING),
                                set_status(*DONE, *detail("SPAWNED"), *IF_FINISHED)],
         {"CC_STATUS_TEST_FINISH_ON_STATUS_WRITE": "1"}),
    ],
    "codex: a prompt lands before the parent's done follow-up": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        # As above, the child finished during the Stop's write, so a second
        # write says idle. But a new prompt was submitted before it landed and
        # its hook wrote "working" with the turn open. The idle was decided on
        # a reading that is now stale, so it carries that reading and iTerm2
        # drops it: the dot keeps showing the running turn, and the ring is
        # left alone too.
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("1 background task running"),
                                           *TURN_CLOSED_COUNTING),
                                set_status(*DONE, *detail("SPAWNED"), *IF_FINISHED)],
         {"CC_STATUS_TEST_FINISH_ON_STATUS_WRITE": "1", "CC_STATUS_TEST_PROMPT_AFTER_JSON": "1"}),
        expect_status("working"),
    ],
    "codex: a prompt lands before a sub-agent's done": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("1 background task running"),
                                           *TURN_CLOSED_COUNTING)]),
        # The decrement's answer said the turn was closed and nothing was
        # left, but a prompt reopened it before the idle could land.
        ("codex/SubagentStop", [background_tasks_delta("-1"),
                                set_status(*DONE, *detail("DONE"), *IF_FINISHED)],
         {"CC_STATUS_TEST_PROMPT_AFTER_JSON": "1"}),
        expect_status("working"),
        ("codex/Stop-hello", [get_background_tasks(),
                              set_status(*DONE, *detail("HELLO"), *TURN_CLOSED)]),
    ],
    "codex: waited sub-agent finishes inside the parent turn": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        # Turn still open: the decrement stored the zero and the display is
        # the parent Stop's business, so there is nothing left to send.
        ("codex/SubagentStop", [background_tasks_delta("-1")]),
        ("codex/Stop-hello", [get_background_tasks(),
                              set_status(*DONE, *detail("HELLO"), *TURN_CLOSED)]),
    ],
    "codex: Esc cancels the turn": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/PreToolUse-Bash", [set_status(*WORKING, *detail(""))]),
        ("codex/Interrupt", [get_background_tasks(),
                             set_status(*IDLE, *detail(""), *TURN_CLOSED)]),
    ],
    "codex: a failed turn's work finishes during its write and it still reads error": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/StopFailure", [get_background_tasks(),
                               set_status(*WORKING, *detail("1 background task running"),
                                          *TURN_CLOSED_COUNTING),
                               set_status(*ERROR, *detail(""), *IF_FINISHED)],
         {"CC_STATUS_TEST_FINISH_ON_STATUS_WRITE": "1"}),
    ],
    "codex: a cancelled turn's work finishes during its write and it still reads idle": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/Interrupt", [get_background_tasks(),
                             set_status(*WORKING, *detail("1 background task running"),
                                        *TURN_CLOSED_COUNTING),
                             set_status(*IDLE, *detail(""), *IF_FINISHED)],
         {"CC_STATUS_TEST_FINISH_ON_STATUS_WRITE": "1"}),
    ],
    "codex: Esc while a detached sub-agent runs": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/Interrupt", [get_background_tasks(),
                             set_status(*WORKING, *detail("1 background task running"),
                                        *TURN_CLOSED_COUNTING)]),
        ("codex/SubagentStop", [background_tasks_delta("-1"),
                                set_status(*DONE, *detail("DONE"), *IF_FINISHED)]),
    ],
    "codex: detached sub-agent is refused permission and stops": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("1 background task running"),
                                           *TURN_CLOSED_COUNTING)]),
        # The child asks permission after the parent stopped; refusing it
        # brings no PostToolUse, so the "waiting" it left is the child's to
        # clear when it stops.
        ("codex/PermissionRequest-apply_patch",
         [set_status(*WAITING, *detail("Allow Edit: Sources/cc-status/main.swift, tests/run.py?"))]),
        ("codex/SubagentStop", [background_tasks_delta("-1"),
                                set_status(*DONE, *detail("DONE"), *IF_FINISHED)]),
    ],
    "codex: failed turn clears turn state": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/StopFailure", [get_background_tasks(),
                                set_status(*ERROR, *detail(""), *TURN_CLOSED)]),
    ],
    "codex: session boundaries": [
        ("codex/SessionStart", [set_status(*IDLE, *detail(""), "--background-tasks=0",
                                           *TURN_CLOSED, boundary=True)]),
        ("codex/SessionEnd", [set_status(*IDLE, *detail(""), "--background-tasks=0",
                                         *TURN_CLOSED, boundary=True)]),
    ],
    "codex: apply_patch permission names the files": [
        ("codex/PermissionRequest-apply_patch",
         [set_status(*WAITING, *detail("Allow Edit: Sources/cc-status/main.swift, tests/run.py?"))]),
    ],
    "codex: sub-agent stops with no turn on record": [
        # No UserPromptSubmit ever ran (hooks installed mid-session, or the
        # session was resumed), so the turn flag is unset. Unset is unknown, not
        # closed: reporting idle here would cut off a turn that is still going.
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/SubagentStop", [background_tasks_delta("-1")]),
    ],
    "codex: utility sub-agent runs while the session is idle": [
        ("codex/SessionStart", [set_status(*IDLE, *detail(""), "--background-tasks=0",
                                           *TURN_CLOSED, boundary=True)]),
        ("codex/Stop-hello", [get_background_tasks(),
                              set_status(*DONE, *detail("HELLO"), *TURN_CLOSED)]),
        # Codex runs utility sub-agents at the prompt; the status must stay
        # done and keep the root turn's message rather than take the utility's.
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/SubagentStop", [background_tasks_delta("-1")]),
    ],
    "codex: sub-agent stops after the display was cleared": [
        ("codex/SessionStart", [set_status(*IDLE, *detail(""), "--background-tasks=0",
                                           *TURN_CLOSED, boundary=True)]),
        FORGET_STATUS,
        # Nothing is displayed, so there is no stale "working" to correct;
        # writing idle would only show the utility agent's message.
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/SubagentStop", [background_tasks_delta("-1")]),
    ],
    "codex: two sub-agents finish together and the slower write lands last": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        ("codex/Stop-spawned", [get_background_tasks(),
                                set_status(*WORKING, *detail("2 background tasks running"),
                                           *TURN_CLOSED_COUNTING)]),
        # This hook counted down to 1, but its sibling reached 0 and wrote
        # idle before this "working" landed. Nothing else will fire, so the
        # status that comes back with the write is what catches it.
        ("codex/SubagentStop", [background_tasks_delta("-1"),
                                set_status(*WORKING, *detail("1 background task running"), "--json"),
                                set_status(*DONE, *detail("DONE"), *IF_FINISHED)],
         {"CC_STATUS_TEST_FINISH_ON_STATUS_WRITE": "1"}),
    ],
    "codex: Esc killed on its timeout still leaves the turn open": [
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/SubagentStart", [set_status("--background-tasks-delta=1")]),
        # Killed after the count read, before the status write. Nothing
        # changed, so the flag still says open: the worst case is a stale
        # "working" that the next turn clears, never a false idle.
        ("codex/Interrupt", [get_background_tasks()],
         {"CC_STATUS_TEST_KILL_AFTER": "1"}),
        ("codex/SubagentStop", [background_tasks_delta("-1")]),
        ("codex/UserPromptSubmit", [set_status(*WORKING, *detail(""), *TURN_OPEN)]),
        ("codex/Stop-hello", [get_background_tasks(),
                              set_status(*DONE, *detail("HELLO"), *TURN_CLOSED)]),
    ],
    "codex: an unhandled snake_case tool reads as words": [
        ("codex/PermissionRequest-read_file",
         [set_status(*WAITING, *detail("Allow Read File?"))]),
    ],
    "claude: plain turn makes no extra it2 calls": [
        ("claude/UserPromptSubmit", [set_status(*WORKING, *detail(""), *EXPIRES)]),
        ("claude/PreToolUse-Bash", [set_status(*WORKING, *detail(""), *EXPIRES)]),
        ("claude/PostToolUse-Bash", [set_status(*WORKING, *detail(""), *EXPIRES)]),
        ("claude/Stop-nobg", [set_status(*DONE, *detail("HELLO"), "--background-tasks=0")]),
    ],
    "claude: the idle nudge leaves a finished turn alone": [
        ("claude/Stop-nobg", [set_status(*DONE, *detail("HELLO"), "--background-tasks=0")]),
        # The nudge has no message; re-sending done would wipe Stop's.
        ("claude/Notification-idle", [get_status()]),
        expect_status("done"),
    ],
    "claude: the idle nudge does not undo the user seeing the result": [
        ("claude/Stop-nobg", [set_status(*DONE, *detail("HELLO"), "--background-tasks=0")]),
        USER_TYPED,
        ("claude/Notification-idle", [get_status()]),
        expect_status("idle"),
    ],
    "claude: a failed turn reports error and the nudge keeps it": [
        ("claude/UserPromptSubmit", [set_status(*WORKING, *detail(""), *EXPIRES)]),
        ("claude/StopFailure", [get_background_tasks(), set_status(*ERROR, *detail(""))]),
        ("claude/Notification-idle", [get_status()]),
        expect_status("error"),
    ],
    "claude: background work survives the idle nudge": [
        ("claude/Stop-bg1", [set_status(*WORKING, *detail("1 background task running"),
                                        "--background-tasks=1")]),
        ("claude/Notification-idle", [get_status(),
                                      set_status(*WORKING, *detail("1 background task running"))]),
        # The stopping agent is still listed as running; excluded by agent_id.
        ("claude/SubagentStop-last", [set_status("--background-tasks=0")]),
        # The last of the background work finished after Stop, so its result
        # is what the user has not seen yet.
        ("claude/Notification-idle", [get_status(), set_status(*DONE, *detail(""))]),
    ],
    "claude: payloads without background_tasks (before 2.1.198)": [
        ("claude/Stop-legacy", [set_status(*DONE, *detail("HELLO"))]),
        ("claude/SubagentStop-legacy", []),
    ],
    "claude: permission and session boundary": [
        ("claude/PermissionRequest-Bash", [set_status(*WAITING, *detail("Allow Bash: rm -rf build?"), *EXPIRES)]),
        ("claude/SessionStart", [set_status(*IDLE, *detail(""), "--background-tasks=0", boundary=True)]),
    ],
}


def build_binary():
    subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    return os.path.join(ROOT, ".build", "release", "cc-status")


def run_scenario(name, steps, binary, workdir):
    session_dir = tempfile.mkdtemp(prefix="session-", dir=workdir)
    log_path = os.path.join(session_dir, "it2.log")
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": session_dir,
        "TERM_SESSION_ID": "w0t0p0:" + SESSION,
        # cc-status forks no it2 unless iTerm2 looks reachable; any IT2_SOCK
        # satisfies that gate (see resolveAddress), and the fake never dials it.
        "IT2_SOCK": os.path.join(session_dir, "unused.sock"),
        "CC_STATUS_TEST_LOG": log_path,
        "CC_STATUS_TEST_STATE": session_dir,
    }
    failures = []
    for step in steps:
        if step == USER_TYPED:
            status_file = os.path.join(session_dir, "status")
            try:
                with open(status_file) as f:
                    shown = f.read().strip()
            except FileNotFoundError:
                shown = None
            if shown in ("done", "error"):
                with open(status_file, "w") as f:
                    f.write("idle\n")
            continue
        if step == FORGET_STATUS:
            status_file = os.path.join(session_dir, "status")
            if os.path.exists(status_file):
                os.remove(status_file)
            continue
        if step[0] == "expect displayed status":
            try:
                with open(os.path.join(session_dir, "status")) as f:
                    shown = f.read().strip()
            except FileNotFoundError:
                shown = None
            if shown != step[1]:
                failures.append("  displayed status\n    expected: %r\n    actual:   %r" % (step[1], shown))
            continue
        fixture, expected = step[0], step[1]
        extra = step[2] if len(step) > 2 else {}
        killed = "CC_STATUS_TEST_KILL_AFTER" in extra
        with open(os.path.join(FIXTURES, fixture + ".json"), "rb") as f:
            payload = f.read()
        open(log_path, "w").close()
        command = [os.path.join(workdir, "cc-status")]
        if fixture.startswith("codex/"):
            command += ["--agent", "codex"]
        # A fresh pty stands in for the agent's terminal, so the progress ring
        # can be checked instead of landing in this one.
        master, slave = pty.openpty()
        terminal = Terminal(master)
        result = subprocess.run([sys.executable, "-c", DETACHED] + command, input=payload,
                                env={**env, **extra},
                                capture_output=True, start_new_session=True, pass_fds=(slave,),
                                preexec_fn=lambda: fcntl.ioctl(slave, termios.TIOCSCTTY, 0))
        os.close(slave)
        terminal.thread.join()
        os.close(master)
        ring = terminal.data
        with open(log_path) as f:
            calls = [line.rstrip("\n").split(ARG_SEPARATOR)[:-1] for line in f if line.strip()]
        problems = []
        if ring != expected_ring(fixture, expected, extra):
            problems.append("terminal output\n      expected: %r\n      actual:   %r"
                            % (expected_ring(fixture, expected, extra), ring))
        if not killed:  # A killed hook has no orderly exit to check.
            if result.returncode != 0:
                problems.append("exit status %d" % result.returncode)
            if result.stdout:  # Codex rejects non-JSON stdout from SessionStart/Stop hooks.
                problems.append("stdout not empty: %r" % result.stdout)
            if result.stderr:
                problems.append("stderr not empty: %r" % result.stderr)
        if calls != expected:
            problems.append("it2 calls\n      expected: %s\n      actual:   %s" % (expected, calls))
        if problems:
            failures.append("  %s\n    %s" % (fixture, "\n    ".join(problems)))
    return failures


def main():
    binary = os.environ.get("CC_STATUS_BIN") or build_binary()
    workdir = tempfile.mkdtemp(prefix="cc-status-tests-")
    shutil.copy(binary, os.path.join(workdir, "cc-status"))
    fake_it2 = os.path.join(workdir, "it2")
    with open(fake_it2, "w") as f:
        f.write(FAKE_IT2)
    os.chmod(fake_it2, 0o755)

    failed = 0
    for name, steps in SCENARIOS.items():
        failures = run_scenario(name, steps, binary, workdir)
        print(("FAIL" if failures else "ok  ") + " " + name)
        for failure in failures:
            print(failure)
        failed += bool(failures)
    shutil.rmtree(workdir)
    print("%d scenarios, %d failed" % (len(SCENARIOS), failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
