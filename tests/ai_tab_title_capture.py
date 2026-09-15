#!/usr/bin/env python3
"""Continuously capture iTerm2 sessions as AI tab-title test cases.

Long-running monitor: every INTERVAL seconds it grabs the frontmost session and
appends it to the corpus the grader reads, but only when the visible screen has
drifted substantially from what was last saved for that session. "Substantially"
is a fuzzy match (difflib ratio, ~edit-distance based): if the current screen is
at least THRESHOLD similar to the last saved one, it is skipped as a near
duplicate. This keeps the corpus diverse without you doing anything but working.

    ~/Library/Application Support/iTerm2/AITabTitleCorpus/corpus.jsonl

Run it from the iTerm2 Scripts menu (it keeps running until iTerm2 stops it) or
from a terminal:

    python3 tests/ai_tab_title_capture.py

Dedup is per session id: switching between two sessions captures each when it
changes, without re-saving a session whose screen you already have.

The record format matches AITabTitleRecord (sources/AITerm/AITabTitleCorpus.swift)
and the context string is assembled the same way AITabTitleGenerator does, so a
captured case replays identically through the grader:

    tools/run_ai_live.sh test_appleIntelligence_tabTitle_gradeCorpus

Requirements: the `iterm2` pip package and iTerm2's Python API enabled
(Settings -> General -> Magic -> Enable Python API). No special build needed;
this uses the shipping API against your normal iTerm2.
"""

import argparse
import asyncio
import difflib
import json
import os
import sys
import time

try:
    import iterm2
except ImportError:
    sys.stderr.write(
        "The 'iterm2' package is required. Install it with:\n"
        "    pip3 install iterm2\n")
    sys.exit(1)

DEFAULT_CORPUS = os.path.expanduser(
    "~/Library/Application Support/iTerm2/AITabTitleCorpus/corpus.jsonl")

# Foreground job names that mean "sitting at a prompt", not "running a program".
# Mirrors the intent of PTYSession.isAtShellPrompt, which the API doesn't expose
# directly; this is a good-enough heuristic for offline capture.
SHELLS = {"zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "-sh",
          "tcsh", "-tcsh", "csh", "-csh", "ksh", "-ksh", "dash"}

MAX_LINES = 60           # bound the screen like the generator does
MIN_SCREEN_CHARS = 3     # skip a nearly-empty screen
DEFAULT_INTERVAL = 60.0  # seconds between polls
DEFAULT_THRESHOLD = 0.9  # skip if this similar (0..1) to the last saved screen


def log(message):
    sys.stderr.write(message + "\n")
    sys.stderr.flush()


async def variable(session, name):
    """Read a session variable, returning None if unset or unavailable."""
    try:
        return await session.async_get_variable(name)
    except Exception:
        return None


def strip_trailing_blank_lines(lines):
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


async def screen_text(session):
    """The visible grid as plain text, trailing blank lines removed.

    The API returns unwritten cells as NUL (\\x00). Mirror iTerm2's own
    extractor (NullPolicyMidlineAsSpaceIgnoreTerminal): turn NULs into spaces
    and strip trailing whitespace per line."""
    contents = await session.async_get_screen_contents()
    lines = []
    for i in range(contents.number_of_lines):
        lines.append(contents.line(i).string.replace("\x00", " ").rstrip())
    lines = strip_trailing_blank_lines(lines)
    if len(lines) > MAX_LINES:
        lines = lines[-MAX_LINES:]
    return "\n".join(lines)


def abbreviating_home(path, home):
    """Abbreviate a leading home directory to ~ (matches the app)."""
    if not home:
        return path
    h = home[:-1] if home.endswith("/") else home
    if path == h:
        return "~"
    if path.startswith(h + "/"):
        return "~" + path[len(h):]
    return path


def build_context(job, command_line, at_prompt, last_command, cwd, user, host, home):
    """Assemble the context block exactly like AITabTitleContext.assembleText."""
    lines = []
    if at_prompt:
        if last_command:
            lines.append("At a shell prompt. The last command run was: " + last_command)
        else:
            lines.append("At a shell prompt.")
    else:
        if job:
            lines.append("Foreground program: " + job)
        if command_line and command_line != job:
            lines.append("Command line: " + command_line)
    if cwd:
        lines.append("Directory: " + abbreviating_home(cwd, home))
    if user and host:
        lines.append("Host: " + user + "@" + host)
    elif host:
        lines.append("Host: " + host)
    return "\n".join(lines)


def current_session(app):
    """The frontmost session, or None if there is no active window/tab."""
    window = app.current_terminal_window
    if window is None:
        return None
    tab = window.current_tab
    if tab is None:
        return None
    return tab.current_session


def similarity(a, b):
    """Fuzzy similarity in [0, 1] between two screens (difflib ratio)."""
    if not a and not b:
        return 1.0
    return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()


async def build_record(session):
    """Snapshot a session into a corpus record, or None if the screen is empty."""
    screen = await screen_text(session)
    if len(screen.strip()) < MIN_SCREEN_CHARS:
        return None

    job = await variable(session, "jobName")
    command_line = await variable(session, "commandLine")
    cwd = await variable(session, "path")
    user = await variable(session, "username")
    host = await variable(session, "hostname")
    last_command = await variable(session, "lastCommand")
    home = await variable(session, "homeDirectory")
    # Candidate extra metadata (recorded for offline A/B; not fed to the model
    # yet). All are nil unless the program/tmux/git-status-component set them.
    window_name = await variable(session, "terminalWindowName")
    icon_name = await variable(session, "terminalIconName")
    git_branch = await variable(session, "user.gitBranch")
    tmux_window = await variable(session, "tab.tmuxWindowName")
    tmux_pane = await variable(session, "tmuxPaneTitle")
    at_prompt = bool(job) and job in SHELLS

    return {
        "timestamp": time.time(),
        "trigger": "apiSnapshot",
        "job": job,
        "commandLine": command_line,
        "atPrompt": at_prompt,
        "lastCommand": last_command,
        "cwd": cwd,
        "user": user,
        "host": host,
        "home": home,
        "windowName": window_name,
        "iconName": icon_name,
        "gitBranch": git_branch,
        "tmuxWindowName": tmux_window,
        "tmuxPaneTitle": tmux_pane,
        "screen": screen,
        "context": build_context(job, command_line, at_prompt, last_command,
                                 cwd, user, host, home),
        # No model was run for an API snapshot; the grader supplies prompts and
        # generates fresh, and treats title as the (absent) baseline.
        "instructions": "",
        "model": "api-snapshot",
        "title": None,
        "latencyMs": 0,
    }


def append_record(record, corpus_path):
    os.makedirs(os.path.dirname(corpus_path), exist_ok=True)
    with open(corpus_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


async def monitor(connection, corpus_path, interval, threshold):
    app = await iterm2.async_get_app(connection)
    last_screen_by_session = {}
    log("ai_tab_title_capture: monitoring every {:.0f}s (dedup threshold {:.2f}) -> {}"
        .format(interval, threshold, corpus_path))

    while True:
        try:
            session = current_session(app)
            if session is not None:
                record = await build_record(session)
                if record is not None:
                    sid = session.session_id
                    prev = last_screen_by_session.get(sid)
                    sim = similarity(record["screen"], prev) if prev is not None else 0.0
                    if prev is None or sim < threshold:
                        append_record(record, corpus_path)
                        last_screen_by_session[sid] = record["screen"]
                        log("saved   sim={:.2f} atPrompt={} job={} last={}".format(
                            sim, record["atPrompt"], record["job"], record["lastCommand"]))
                    else:
                        log("skipped sim={:.2f} (too similar to last saved)".format(sim))
        except Exception as exc:  # keep the monitor alive across transient errors
            log("error: {}".format(exc))
        await asyncio.sleep(interval)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", default=DEFAULT_CORPUS,
                        help="corpus JSONL file to append to (default: %(default)s)")
    parser.add_argument("--interval", type=float, default=DEFAULT_INTERVAL,
                        help="seconds between polls (default: %(default)s)")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                        help="skip if the screen is at least this similar, 0..1 "
                             "(default: %(default)s)")
    # parse_known_args so args injected by the iTerm2 Scripts menu don't error.
    args, _ = parser.parse_known_args()

    async def run(connection):
        await monitor(connection, args.output, args.interval, args.threshold)

    iterm2.run_until_complete(run)


if __name__ == "__main__":
    main()
