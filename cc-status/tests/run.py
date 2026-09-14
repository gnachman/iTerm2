#!/usr/bin/env python3
"""End-to-end tests for cc-status.

Feeds recorded hook payloads (tests/fixtures/<agent>/*.json, from Claude Code
2.1.201 and Codex CLI 0.154, paths scrubbed) through the built binary and
checks the exact it2 calls it makes. cc-status looks for it2 next to its own
executable, so the binary is copied beside a fake it2 that logs each call and
keeps the state the real one keeps (background-task count, session variables).

    swift build -c release && python3 tests/run.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "tests", "fixtures")
SESSION = "TEST-SESSION"
ARG_SEPARATOR = "\x1f"

FAKE_IT2 = r'''#!/bin/sh
# Fake it2: log argv (one line per call, args separated by \x1f) and keep the
# state cc-status reads back: the background-task count and user variables.
printf '%s\037' "$@" >> "$CC_STATUS_TEST_LOG"
printf '\n' >> "$CC_STATUS_TEST_LOG"
state="$CC_STATUS_TEST_STATE"
case "$1 $2" in
    "set-status "*)
        while [ $# -gt 0 ]; do
            if [ "$1" = "--background-tasks" ]; then
                printf '%s\n' "$2" > "$state/background-tasks"
            fi
            shift
        done
        echo "Session status updated."
        ;;
    "session get-background-tasks")
        cat "$state/background-tasks" 2>/dev/null || echo 0
        ;;
    "session set-var")
        printf '%s\n' "$4" > "$state/var-$3"
        echo "Set $3 = $4"
        ;;
    "session get-var")
        if [ -f "$state/var-$3" ]; then
            cat "$state/var-$3"
        else
            echo "Variable '$3' not set"
        fi
        ;;
    *)
        echo "fake it2: unexpected command: $*" >&2
        exit 1
        ;;
esac
'''

WORKING = ["--status", "working", "--dot-color", "#ff9500", "--text-color", "#ff9500"]
WAITING = ["--status", "waiting", "--dot-color", "#5f87ff", "--text-color", "#5f87ff"]
IDLE = ["--status", "idle", "--dot-color", "#00d75f", "--text-color", "#888888"]
TURN_OPEN = "user.ccStatusTurnOpen"


def set_status(*args):
    return ["set-status", "--session", SESSION, *args]


def get_background_tasks():
    return ["session", "get-background-tasks", "-s", SESSION]


def set_turn_open(value):
    return ["session", "set-var", TURN_OPEN, value, "--session", SESSION]


def get_turn_open():
    return ["session", "get-var", TURN_OPEN, "--session", SESSION]


# (fixture, expected it2 calls in order). A scenario runs its steps against one
# fake session, so state stored by an earlier step is visible to later ones.
SCENARIOS = {
    "codex: plain turn": [
        ("codex/UserPromptSubmit", [set_turn_open("1"), set_status(*WORKING, "--detail", "")]),
        ("codex/PreToolUse-Bash", [set_status(*WORKING, "--detail", "")]),
        ("codex/PostToolUse-Bash", [set_status(*WORKING, "--detail", "")]),
        ("codex/Stop-hello", [get_background_tasks(), set_turn_open("0"),
                              set_status(*IDLE, "--detail", "HELLO")]),
    ],
    "codex: detached sub-agent outlives the parent turn": [
        ("codex/UserPromptSubmit", [set_turn_open("1"), set_status(*WORKING, "--detail", "")]),
        ("codex/PreToolUse-spawn_agent", [set_status(*WORKING, "--detail", "")]),
        ("codex/SubagentStart", [get_background_tasks(),
                                 set_status(*WORKING, "--background-tasks", "1")]),
        # Parent goes idle while the child runs: stay working.
        ("codex/Stop-spawned", [get_background_tasks(), set_turn_open("0"),
                                set_status(*WORKING, "--detail", "1 background task running")]),
        # Child finishes; nothing else will fire, so SubagentStop reports idle.
        ("codex/SubagentStop", [get_background_tasks(), get_turn_open(),
                                set_status(*IDLE, "--detail", "DONE", "--background-tasks", "0")]),
    ],
    "codex: waited sub-agent finishes inside the parent turn": [
        ("codex/UserPromptSubmit", [set_turn_open("1"), set_status(*WORKING, "--detail", "")]),
        ("codex/SubagentStart", [get_background_tasks(),
                                 set_status(*WORKING, "--background-tasks", "1")]),
        # Turn still open: store the zero, leave the display to the parent's Stop.
        ("codex/SubagentStop", [get_background_tasks(), get_turn_open(),
                                set_status("--background-tasks", "0")]),
        ("codex/Stop-hello", [get_background_tasks(), set_turn_open("0"),
                              set_status(*IDLE, "--detail", "HELLO")]),
    ],
    "codex: Esc cancels the turn": [
        ("codex/UserPromptSubmit", [set_turn_open("1"), set_status(*WORKING, "--detail", "")]),
        ("codex/PreToolUse-Bash", [set_status(*WORKING, "--detail", "")]),
        ("codex/Interrupt", [get_background_tasks(), set_turn_open("0"),
                             set_status(*IDLE, "--detail", "")]),
    ],
    "codex: Esc while a detached sub-agent runs": [
        ("codex/UserPromptSubmit", [set_turn_open("1"), set_status(*WORKING, "--detail", "")]),
        ("codex/SubagentStart", [get_background_tasks(),
                                 set_status(*WORKING, "--background-tasks", "1")]),
        ("codex/Interrupt", [get_background_tasks(), set_turn_open("0"),
                             set_status(*WORKING, "--detail", "1 background task running")]),
        ("codex/SubagentStop", [get_background_tasks(), get_turn_open(),
                                set_status(*IDLE, "--detail", "DONE", "--background-tasks", "0")]),
    ],
    "codex: session boundaries": [
        ("codex/SessionStart", [set_status(*IDLE, "--detail", "", "--background-tasks", "0")]),
        ("codex/SessionEnd", [set_status(*IDLE, "--detail", "", "--background-tasks", "0")]),
    ],
    "codex: apply_patch permission names the files": [
        ("codex/PermissionRequest-apply_patch",
         [set_status(*WAITING, "--detail", "Allow Edit: Sources/cc-status/main.swift, tests/run.py?")]),
    ],
    "claude: plain turn makes no extra it2 calls": [
        ("claude/UserPromptSubmit", [set_status(*WORKING, "--detail", "")]),
        ("claude/PreToolUse-Bash", [set_status(*WORKING, "--detail", "")]),
        ("claude/PostToolUse-Bash", [set_status(*WORKING, "--detail", "")]),
        ("claude/Stop-nobg", [set_status(*IDLE, "--detail", "HELLO", "--background-tasks", "0")]),
    ],
    "claude: background work survives the idle nudge": [
        ("claude/Stop-bg1", [set_status(*WORKING, "--detail", "1 background task running",
                                        "--background-tasks", "1")]),
        ("claude/Notification-idle", [get_background_tasks(),
                                      set_status(*WORKING, "--detail", "1 background task running")]),
        # The stopping agent is still listed as running; excluded by agent_id.
        ("claude/SubagentStop-last", [set_status("--background-tasks", "0")]),
        ("claude/Notification-idle", [get_background_tasks(), set_status(*IDLE, "--detail", "")]),
    ],
    "claude: payloads without background_tasks (before 2.1.198)": [
        ("claude/Stop-legacy", [set_status(*IDLE, "--detail", "HELLO")]),
        ("claude/SubagentStop-legacy", []),
    ],
    "claude: permission and session boundary": [
        ("claude/PermissionRequest-Bash", [set_status(*WAITING, "--detail", "Allow Bash: rm -rf build?")]),
        ("claude/SessionStart", [set_status(*IDLE, "--detail", "", "--background-tasks", "0")]),
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
        "CC_STATUS_TEST_LOG": log_path,
        "CC_STATUS_TEST_STATE": session_dir,
    }
    failures = []
    for fixture, expected in steps:
        with open(os.path.join(FIXTURES, fixture + ".json"), "rb") as f:
            payload = f.read()
        open(log_path, "w").close()
        # start_new_session drops the controlling terminal so the OSC progress
        # write to /dev/tty is skipped instead of landing in this terminal.
        result = subprocess.run([os.path.join(workdir, "cc-status")], input=payload, env=env,
                                capture_output=True, start_new_session=True)
        with open(log_path) as f:
            calls = [line.rstrip("\n").split(ARG_SEPARATOR)[:-1] for line in f if line.strip()]
        problems = []
        if result.returncode != 0:
            problems.append("exit status %d" % result.returncode)
        if result.stdout:  # Codex rejects non-JSON stdout from SessionStart/Stop hooks.
            problems.append("stdout not empty: %r" % result.stdout)
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
