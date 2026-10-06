#!/usr/bin/env python3
# End-to-end check that a tmux integration connection survives a window that has only floating
# panes (tmux 3.8 and later), both when it becomes floats-only while attached and when attaching
# to it. Run it through devapi.sh so it reaches the dev instance:
#
#   tests/floating_panes/devapi.sh tests/floating_panes/tmux_floats_only_e2e.py [path-to-tmux]
#
# The tmux defaults to ~/git/tmux/tmux. It runs on its own socket (-L fp-e2e) and that server is
# killed at the end. Prints PASS or FAIL lines and exits nonzero on failure.
import asyncio
import os
import subprocess
import sys

import iterm2

TMUX = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/git/tmux/tmux")
SOCKET = "fp-e2e"
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
    tmux("kill-server")
    app = await iterm2.async_get_app(connection)
    gateway = app.current_terminal_window.current_tab.current_session
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

    async def detached():
        return len(await connections()) == 0

    await gateway.async_send_text(f"{TMUX} -L {SOCKET} -f /dev/null -CC new -s e2e -x 100 -y 30 'sleep 600'\n")
    check(await wait_for(attached), "attached with tmux -CC")

    tmux("new-pane", "-t", "e2e", "sleep 600")
    out = tmux("list-panes", "-t", "e2e", "-F", "#{pane_id} #{pane_floating_flag}").stdout.split()
    check(out == ["%0", "0", "%1", "1"], f"window has one tiled and one floating pane: {out}")

    tmux("kill-pane", "-t", "%0")
    layout = tmux("list-windows", "-t", "e2e", "-F", "#{window_layout}").stdout.strip()
    check(layout.startswith("{"), "window is floats-only")
    await asyncio.sleep(1.5)
    check(await attached(), "connection survives the window becoming floats-only")

    (conn,) = await connections()
    await conn.async_send_command("detach-client")
    check(await wait_for(detached), "detached")

    await gateway.async_send_text(f"{TMUX} -L {SOCKET} -CC attach -t e2e\n")
    check(await wait_for(attached), "reattached to a session whose only window is floats-only")
    await asyncio.sleep(1.5)
    check(await attached(), "connection survives attaching to a floats-only window")

    connections_now = await connections()
    if connections_now:
        await connections_now[0].async_send_command("kill-server")
    else:
        tmux("kill-server")
    await wait_for(detached)


iterm2.run_until_complete(main)
sys.exit(1 if failures else 0)
