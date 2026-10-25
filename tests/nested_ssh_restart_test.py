#!/usr/bin/env python3
# Restarting iTerm2 with a nested SSH Integration connection open.
#
# Launches a built iTerm2 under its own suite, opens `it2ssh localhost` inside `it2ssh localhost`,
# starts a flood in the inner shell, then kills iTerm2 (SIGKILL, as a crash would) and launches it
# again. The session comes back from its arrangement while its job keeps running in the job
# server. The test then checks, in the restored session:
#   - Ctrl-C stops the flood and the inner shell answers,
#   - it is still the inner shell, and its connection still frames output,
#   - `exit` returns to the outer shell, and again to this Mac.
# Each shell is told apart by a variable the test sets in it, and by its IT2_SOCK where the app
# sets one.
#
# Requirements: the iterm2 Python package, key-based `ssh localhost`, ~/.iterm2/it2ssh, and the
# Python API without authentication for the suite's Application Support directory: a root-owned
# ~/Library/Application Support/<suite>/disable-automation-auth holding the hex of its own path,
# a space, and 61DF88DC-3423-4823-B725-22570E01C027. The suite is its own, so the test can clear
# its saved windows without touching any other iTerm2's.
#
# Run it where the app can open windows, e.g. on a test VM:
#   tools/run_tests_vm.sh --host vm2 -- python3 tests/nested_ssh_restart_test.py
#
# Options: --app PATH (default: the newest Development build in DerivedData), --suite NAME,
# --it2ssh PATH (default: ~/.iterm2/it2ssh), --no-flood (restart an idle inner shell),
# --answer-timeout SECONDS (how long the restored shell has to answer; default 60),
# --relaunch-app PATH (the app launched after the kill; default: the same app).
#
# To compare with a release, pass its app and its own it2ssh, e.g.
#   --app ~/Applications/iTerm2-3.7.5.app \
#   --it2ssh ~/Applications/iTerm2-3.7.5.app/Contents/Resources/utilities/it2ssh
# Keep the release in an Applications folder: elsewhere it offers to move itself there at launch,
# and that alert blocks it.
# Add --relaunch-app with a newer build to restore what the release saved, as after an upgrade.

import argparse
import asyncio
import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import time

import iterm2

IT2SSH = os.path.expanduser("~/.iterm2/it2ssh")


def find_app():
    candidates = glob.glob(os.path.expanduser(
        "~/Library/Developer/Xcode/DerivedData/iTerm2-*/Build/Products/*/Development/iTerm2.app"))
    if not candidates:
        sys.exit("No Development build of iTerm2.app in DerivedData; pass --app")
    return max(candidates, key=os.path.getmtime)


class Instance:
    def __init__(self, app, suite, log):
        self.app = app
        self.suite = suite
        self.log = log
        self.process = None

    @property
    def support(self):
        return os.path.expanduser(f"~/Library/Application Support/{self.suite}")

    def clean(self):
        """Removes what an earlier run left: its saved windows, and the job servers holding its
        jobs. Either would come back at launch as a session whose job is gone, and the alert
        about sessions ending so soon would block the app."""
        shutil.rmtree(os.path.join(self.support, "SavedState"), ignore_errors=True)
        subprocess.run(["pkill", "-9", "-f", os.path.join(self.support, "iterm2-daemon-")])
        for socket in glob.glob(os.path.join(self.support, "iterm2-daemon-*.socket*")):
            os.remove(socket)

    def configure(self):
        self.clean()
        for key, kind, value in [("EnableAPIServer", "bool", "true"),
                                 # Restore windows at launch, as after a crash.
                                 ("NSQuitAlwaysKeepsWindows", "bool", "true"),
                                 ("SUEnableAutomaticChecks", "bool", "false")]:
            subprocess.run(["defaults", "write", self.suite, key, "-" + kind, value], check=True)

    def launch(self):
        self.process = subprocess.Popen(
            [os.path.join(self.app, "Contents/MacOS/iTerm2"), "-suite", self.suite],
            stdout=self.log, stderr=subprocess.STDOUT)

    def kill(self):
        if self.process and self.process.poll() is None:
            os.kill(self.process.pid, signal.SIGKILL)
            self.process.wait()


async def connect(timeout=60):
    deadline = time.monotonic() + timeout
    while True:
        try:
            return await iterm2.Connection.async_create()
        except Exception:
            if time.monotonic() > deadline:
                raise
            await asyncio.sleep(0.5)


async def screen(session):
    contents = await session.async_get_screen_contents()
    return "\n".join(contents.line(i).string for i in range(contents.number_of_lines))


async def wait_for(session, pattern, timeout):
    """Waits for a line matching `pattern` and returns its match, or None."""
    deadline = time.monotonic() + timeout
    regex = re.compile(pattern)
    while time.monotonic() < deadline:
        for line in (await screen(session)).split("\n"):
            match = regex.search(line)
            if match:
                return match
        await asyncio.sleep(0.25)
    return None


async def ask(session, tag, timeout):
    """Runs an echo that prints a marker, the shell's hop (set by `mark`) and its IT2_SOCK.
    Returns "hop|socket", or None if the shell does not answer."""
    await session.async_send_text(
        f"echo \"{tag}-$((6*7)) sock=[${{RESTART_TEST_HOP:-local}}|$IT2_SOCK]\"\n")
    match = await wait_for(session, rf"{tag}-42 sock=\[([^\]]*)\]", timeout)
    if not match:
        text = "\n".join(line for line in (await screen(session)).split("\n") if line.strip())
        print(f"no answer to {tag}; the screen shows:\n{text}", flush=True)
        return None
    return match.group(1)


async def mark(session, hop):
    """Sets a variable in the current shell, not exported, that names its hop."""
    await session.async_send_text(f"RESTART_TEST_HOP={hop}\n")


async def is_up(session, identity, hop):
    """Whether a shell answered as `hop`, inside an SSH Integration connection that frames its
    output. IT2_SOCK is not enough: 3.7.5 does not set it."""
    if not identity or identity.partition("|")[0] != hop:
        return False
    return int(await session.async_get_variable("sshIntegrationLevel") or 0) == 2


class Failed(Exception):
    pass


def check(condition, message):
    print(("ok   " if condition else "FAIL ") + message, flush=True)
    if not condition:
        raise Failed(message)


async def before_restart(state, options):
    connection = await connect()
    window = await iterm2.Window.async_create(connection)
    session = window.current_tab.current_session
    state["session_id"] = session.session_id
    local = await ask(session, "local", 30)
    check(local is not None, "the local shell answers")

    await session.async_send_text(f"{options.it2ssh} -A localhost\n")
    await asyncio.sleep(5)
    await mark(session, "outer")
    outer = await ask(session, "outer", 60)
    check(await is_up(session, outer, "outer"), f"the outer connection is up ({outer})")

    await session.async_send_text(f"{options.it2ssh} localhost\n")
    await asyncio.sleep(5)
    await mark(session, "inner")
    inner = await ask(session, "inner", 60)
    check(await is_up(session, inner, "inner"), f"the inner connection is up ({inner})")
    state["outer"], state["inner"] = outer, inner

    if options.flood:
        await session.async_send_text("yes restart-flood\n")
        await asyncio.sleep(3)


async def after_restart(state, options):
    connection = await connect()
    app = await iterm2.async_get_app(connection)
    session = None
    deadline = time.monotonic() + 30
    while session is None and time.monotonic() < deadline:
        session = app.get_session_by_id(state["session_id"])
        if session is None:
            await asyncio.sleep(0.5)
            await app.async_refresh()
    if session is None:
        for window in app.terminal_windows:
            for tab in window.tabs:
                for candidate in tab.sessions:
                    text = [l for l in (await screen(candidate)).split("\n") if l.strip()]
                    print(f"found session {candidate.session_id}: {text[-6:]}", flush=True)
        print(f"wanted {state['session_id']}", flush=True)
    check(session is not None, "the session is restored")

    start = time.monotonic()
    if options.flood:
        await session.async_send_text("\x03")
    identity = await ask(session, "after", options.answer_timeout)
    elapsed = time.monotonic() - start
    what = "Ctrl-C stops the flood and the shell answers" if options.flood else "the shell answers"
    check(identity is not None, f"{what} ({elapsed:.1f} s)")
    check(identity == state["inner"] and await is_up(session, identity, "inner"),
          f"it is the inner shell, still framed ({identity})")

    await session.async_send_text("exit\n")
    await asyncio.sleep(2)
    identity = await ask(session, "back-outer", 30)
    check(identity == state["outer"], f"exit returns to the outer shell ({identity})")

    await session.async_send_text("exit\n")
    await asyncio.sleep(2)
    identity = await ask(session, "back-local", 30)
    check(identity is not None and identity.startswith("local|"),
          f"exit again returns to this Mac ({identity})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=None)
    parser.add_argument("--suite", default="iterm2-restart-test")
    parser.add_argument("--it2ssh", default=IT2SSH)
    parser.add_argument("--no-flood", dest="flood", action="store_false")
    parser.add_argument("--answer-timeout", type=float, default=60)
    parser.add_argument("--relaunch-app", default=None)
    options = parser.parse_args()
    options.it2ssh = os.path.expanduser(options.it2ssh)
    if not os.access(options.it2ssh, os.X_OK):
        sys.exit(f"{options.it2ssh} is not installed")
    os.environ["IT2_SUITE"] = options.suite
    with open("/tmp/nested_ssh_restart_test.log", "w") as log:
        instance = Instance(os.path.expanduser(options.app) if options.app else find_app(),
                            options.suite, log)
        print(f"app: {instance.app}", flush=True)
        instance.configure()
        state = {}
        try:
            instance.launch()
            asyncio.run(before_restart(state, options))
            # iTerm2 saves its windows when it stops being the active app (or quits), which in
            # use happens long before a crash. Switch to another app so it saves.
            subprocess.run(["open", "-a", "Finder"], check=True)
            time.sleep(5)
            instance.kill()
            if options.relaunch_app:
                instance.app = os.path.expanduser(options.relaunch_app)
            print(f"killed iTerm2; launching {instance.app}", flush=True)
            instance.launch()
            asyncio.run(after_restart(state, options))
            print("PASS", flush=True)
            return 0
        except Failed:
            return 1
        finally:
            instance.kill()
            instance.clean()


if __name__ == "__main__":
    sys.exit(main())
