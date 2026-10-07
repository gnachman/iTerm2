#!/usr/bin/env python3
# Checks that a tmux without JSON layouts (3.7 and older), which ignores the new-layouts opt-in and
# keeps sending v1 layouts, still works. Run it through devapi.sh so it reaches the dev instance:
#
#   PYTHONPATH=api/library/python/iterm2 tests/floating_panes/devapi.sh tests/floating_panes/tmux_v1_e2e.py [path-to-tmux]
#
# The tmux defaults to /opt/homebrew/bin/tmux. It runs on its own socket (-L fp-v1) and that server
# is killed at the end. Prints PASS or FAIL lines and exits nonzero on failure.
import asyncio
import os
import subprocess
import sys

import iterm2

TMUX = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "/opt/homebrew/bin/tmux")
SOCKET = "fp-v1"
failures = []


def tmux(*args):
    return subprocess.run([TMUX, "-L", SOCKET] + list(args), capture_output=True, text=True)


def check(condition, message):
    print(("PASS " if condition else "FAIL ") + message, flush=True)
    if not condition:
        failures.append(message)


async def wait_for(predicate, timeout=10.0):
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        if await predicate():
            return True
        await asyncio.sleep(0.2)
    return False


async def main(connection):
    print(f"Using {TMUX}: {subprocess.run([TMUX, '-V'], capture_output=True, text=True).stdout.strip()}")
    tmux("kill-server")
    window = await iterm2.Window.async_create(connection)
    app = await iterm2.async_get_app(connection)
    gateway = app.get_window_by_id(window.window_id).current_tab.current_session
    # Typing before the shell is ready can lose the command.
    for _ in range(50):
        contents = await gateway.async_get_screen_contents()
        if any(contents.line(i).string.strip() for i in range(contents.number_of_lines)):
            break
        await asyncio.sleep(0.2)

    async def connections():
        return await iterm2.async_get_tmux_connections(connection)

    async def attached():
        return len(await connections()) == 1

    await gateway.async_send_text(
        f"{TMUX} -L {SOCKET} -f /dev/null -CC new -s v1 -x 120 -y 36 'sleep 600'\n")
    check(await wait_for(attached), "attached with tmux -CC")

    async def tmux_tab():
        await app.async_refresh()
        for w in app.terminal_windows:
            for t in w.tabs:
                if t.tmux_window_id is not None and t.tmux_window_id != "-1":
                    return t
        return None

    async def has_tab():
        return await tmux_tab() is not None

    check(await wait_for(has_tab), "a tmux tab appears")

    tmux("split-window", "-h", "-t", "v1", "sleep 600")

    async def two_panes():
        tab = await tmux_tab()
        return tab is not None and len(tab.sessions) == 2

    check(await wait_for(two_panes), "a split in tmux shows two tiled panes")
    tab = await tmux_tab()
    check(len(tab.floating_sessions) == 0, "there are no floating panes")

    # tmux 3.7 has floating panes but sends them in v1 layouts. They show as floats, not as split
    # panes, and can't be moved from iTerm2.
    floating = tmux("new-pane", "-t", "v1", "-P", "-F", "#{pane_id}", "-x", "30", "-y", "8", "sleep 600")
    if floating.returncode == 0:
        async def shows_float():
            tab = await tmux_tab()
            return tab is not None and len(tab.floating_sessions) == 1 and len(tab.sessions) == 2

        check(await wait_for(shows_float), f"tmux 3.7's float {floating.stdout.strip()} shows as a float")
        tmux("kill-pane", "-t", floating.stdout.strip())

        async def float_gone():
            tab = await tmux_tab()
            return tab is not None and len(tab.floating_sessions) == 0

        check(await wait_for(float_gone), "killing it removes the float")
    else:
        print("This tmux has no floating panes; skipping the float check")

    panes = tmux("list-panes", "-t", "v1", "-F", "#{pane_id}").stdout.split()
    tmux("resize-pane", "-t", panes[0], "-x", "40")

    async def resized():
        tab = await tmux_tab()
        if tab is None:
            return False
        widths = sorted(s.grid_size.width for s in tab.sessions)
        return 40 in widths

    check(await wait_for(resized), "a resize in tmux resizes the pane")

    tmux("kill-pane", "-t", panes[1])

    async def one_pane():
        tab = await tmux_tab()
        return tab is not None and len(tab.sessions) == 1

    check(await wait_for(one_pane), "killing a pane in tmux removes it")
    check(await attached(), "still attached")
    conns = await connections()
    if conns:
        await conns[0].async_send_command("kill-server")
    await asyncio.sleep(1)
    await window.async_close(force=True)


iterm2.run_until_complete(main)
if failures:
    print(f"{len(failures)} FAILED")
    sys.exit(1)
print("ALL PASSED")
