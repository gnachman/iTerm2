#!/usr/bin/env python3
# End-to-end check of the less common ways tmux makes and shows floating panes: borderless floats,
# modal floats, window resizes, a second plain client, and detaching and reattaching. Run it through
# devapi.sh so it reaches the dev instance:
#
#   PYTHONPATH=api/library/python/iterm2 tests/floating_panes/devapi.sh tests/floating_panes/tmux_floats_robustness_e2e.py [path-to-tmux]
#
# display-popup, which now opens a modal float, isn't covered: run from outside tmux it waits but
# makes no pane, with or without a control client attached. new-pane -O makes the same kind of pane.
#
# The tmux defaults to ~/git/tmux/tmux (it needs floating panes). It runs on its own socket
# (-L fp-rob) and that server is killed at the end. Prints PASS or FAIL lines and exits nonzero on
# failure.
import asyncio
import os
import subprocess
import sys

import iterm2

TMUX = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/git/tmux/tmux")
SOCKET = "fp-rob"
failures = []


def tmux(*args):
    return subprocess.run([TMUX, "-L", SOCKET] + list(args), capture_output=True, text=True)


def tmux_floats():
    rows = tmux("list-panes", "-t", "rob", "-F", "#{pane_id} #{pane_floating_flag}").stdout.splitlines()
    return sorted(r.split()[0] for r in rows if r.split() and r.split()[1] == "1")


def new_float(*args):
    return tmux("new-pane", "-t", "rob", "-P", "-F", "#{pane_id}", *args, "sleep 600").stdout.strip()


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


async def wait_for_shell(session):
    # Typing before the shell is ready can lose the command.
    for _ in range(50):
        contents = await session.async_get_screen_contents()
        if any(contents.line(i).string.strip() for i in range(contents.number_of_lines)):
            return
        await asyncio.sleep(0.2)


async def main(connection):
    tmux("kill-server")
    app = await iterm2.async_get_app(connection)
    window = await iterm2.Window.async_create(connection)
    await app.async_refresh()
    gateway = app.get_window_by_id(window.window_id).current_tab.current_session
    await wait_for_shell(gateway)

    async def connections():
        return await iterm2.async_get_tmux_connections(connection)

    async def attached():
        return len(await connections()) == 1

    async def detached():
        return len(await connections()) == 0

    await gateway.async_send_text(
        f"{TMUX} -L {SOCKET} -f /dev/null -CC new -s rob -x 120 -y 36 'sleep 600'\n")
    check(await wait_for(attached), "attached with tmux -CC")

    async def tmux_tab():
        await app.async_refresh()
        for w in app.terminal_windows:
            for t in w.tabs:
                if t.tmux_window_id is not None and t.tmux_window_id != "-1":
                    return t
        return None

    async def floats_by_pane():
        tab = await tmux_tab()
        if not tab:
            return {}
        result = {}
        for s in tab.floating_sessions:
            result["%" + str(await s.async_get_variable("tmuxWindowPane"))] = s
        return result

    async def shows_floats(expected):
        return sorted((await floats_by_pane()).keys()) == sorted(expected)

    # A borderless float has no title bar; one with a border and the same grid does. tmux takes a
    # float's border out of the size it is given.
    bordered = new_float("-x", "32", "-y", "10")
    borderless = new_float("-x", "30", "-y", "8", "-B", "none")

    async def heights_differ():
        floats = await floats_by_pane()
        if bordered not in floats or borderless not in floats:
            return False
        a, b = floats[bordered], floats[borderless]
        same_grid = (a.grid_size.width, a.grid_size.height) == (b.grid_size.width, b.grid_size.height)
        return same_grid and b.frame.size.height < a.frame.size.height

    check(await wait_for(heights_differ), "a float made with -B none has no title bar")

    # A modal float is an ordinary float.
    modal = new_float("-O")
    check(modal.startswith("%"), f"tmux made a modal float {modal}")
    check(await wait_for(lambda: shows_floats(tmux_floats())), "the modal float appears")
    tmux("kill-pane", "-t", modal)
    check(await wait_for(lambda: shows_floats(tmux_floats())), "closing the modal float removes it")

    # Resizing the window resizes tmux's window and keeps the floats.
    def window_size():
        out = tmux("display", "-p", "-t", "rob", "#{window_width} #{window_height}").stdout.split()
        return tuple(int(x) for x in out)

    # tmux integration opened the tab in a window of its own.
    before = window_size()
    tab = await tmux_tab()
    tmux_window = next(w for w in app.terminal_windows if any(t.tab_id == tab.tab_id for t in w.tabs))
    frame = await tmux_window.async_get_frame()
    await tmux_window.async_set_frame(iterm2.util.Frame(
        frame.origin, iterm2.util.Size(frame.size.width - 200, frame.size.height - 150)))

    async def tmux_window_shrank():
        after = window_size()
        return after[0] < before[0] and after[1] < before[1]

    check(await wait_for(tmux_window_shrank), f"shrinking the window shrinks tmux's: {before} -> {window_size()}")
    check(await wait_for(lambda: shows_floats(tmux_floats())), "the floats survive the resize")

    # A second, plain client doesn't disturb the control client.
    plain_window = await iterm2.Window.async_create(connection)
    await app.async_refresh()
    plain = app.get_window_by_id(plain_window.window_id).current_tab.current_session
    await wait_for_shell(plain)
    await plain.async_send_text(f"{TMUX} -L {SOCKET} attach -t rob\n")

    async def two_clients():
        return len(tmux("list-clients").stdout.splitlines()) == 2

    check(await wait_for(two_clients), "a plain client attaches too")
    another = new_float("-x", "20", "-y", "5")
    check(await wait_for(lambda: shows_floats(tmux_floats())), f"a float made with two clients appears: {another}")
    check(await attached(), "the control client stays attached")

    for line in tmux("list-clients", "-F", "#{client_name} #{client_control_mode}").stdout.splitlines():
        name, control = line.split()
        if control == "0":
            tmux("detach-client", "-t", name)
    await asyncio.sleep(1)
    await plain_window.async_close(force=True)

    # Detach and reattach: the floats come back.
    conns = await connections()
    await conns[0].async_send_command("detach-client")
    check(await wait_for(detached), "detached")
    await asyncio.sleep(1)
    await app.async_refresh()
    gateway = app.get_window_by_id(window.window_id).current_tab.current_session
    await gateway.async_send_text(f"{TMUX} -L {SOCKET} -CC attach -t rob\n")
    check(await wait_for(attached), "reattached")
    check(await wait_for(lambda: shows_floats(tmux_floats())),
          f"the floats come back on reattaching: {sorted((await floats_by_pane()).keys())} vs {tmux_floats()}")

    async def borderless_after_reattach():
        return await heights_differ()

    check(await wait_for(borderless_after_reattach), "the borderless float is still borderless")

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
