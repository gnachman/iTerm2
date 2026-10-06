#!/usr/bin/env python3
# End-to-end check of floating panes in a tmux integration window. Run it through devapi.sh so it
# reaches the dev instance:
#
#   tests/floating_panes/devapi.sh tests/floating_panes/tmux_floats_e2e.py [path-to-tmux]
#
# The tmux defaults to ~/git/tmux/tmux (it needs floating panes). It runs on its own socket
# (-L fp-tmux) and that server is killed at the end. Prints PASS or FAIL lines and exits nonzero on
# failure.
import asyncio
import os
import subprocess
import sys

import iterm2

TMUX = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/git/tmux/tmux")
SOCKET = "fp-tmux"
failures = []


def tmux(*args):
    return subprocess.run([TMUX, "-L", SOCKET] + list(args), capture_output=True, text=True)


def pane_info(pane):
    out = tmux("display", "-p", "-t", pane,
               "#{pane_width} #{pane_height} #{pane_left} #{pane_top} #{pane_floating_flag}").stdout.split()
    return [int(x) for x in out]


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
    window = await iterm2.Window.async_create(connection)
    await asyncio.sleep(0.5)
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
        f"{TMUX} -L {SOCKET} -f /dev/null -CC new -s fp -x 120 -y 36 'sleep 600'\n")
    check(await wait_for(attached), "attached with tmux -CC")
    await asyncio.sleep(1)

    async def tmux_tab():
        await app.async_refresh()
        for w in app.terminal_windows:
            for t in w.tabs:
                if t.tmux_window_id is not None and t.tmux_window_id != "-1":
                    return t
        return None

    # A float appears.
    tmux("split-window", "-h", "-t", "fp", "sleep 600")
    tmux("new-pane", "-t", "fp", "sleep 600")
    panes = tmux("list-panes", "-t", "fp", "-F", "#{pane_id} #{pane_floating_flag}").stdout.split()
    float_id = panes[panes.index("1") - 1]

    async def has_float():
        tab = await tmux_tab()
        return tab is not None and len(tab.floating_sessions) == 1

    check(await wait_for(has_float), f"the tmux float {float_id} appears as a floating pane")
    tab = await tmux_tab()
    check(len(tab.sessions) == 2, f"the two tiled panes stay tiled: {len(tab.sessions)}")
    float_session = tab.floating_sessions[0]
    w, h, x, y, _ = pane_info(float_id)
    check((float_session.grid_size.width, float_session.grid_size.height) == (w, h),
          f"the float has tmux's grid {w}x{h}: "
          f"{float_session.grid_size.width}x{float_session.grid_size.height}")
    first_frame = (float_session.frame.origin.x, float_session.frame.origin.y)

    # tmux moves and resizes it.
    tmux("move-pane", "-t", float_id, "-R", "5", "-D", "2")
    tmux("resize-pane", "-t", float_id, "-R", "4")

    async def moved():
        tab = await tmux_tab()
        if not tab or not tab.floating_sessions:
            return False
        s = tab.floating_sessions[0]
        return (s.grid_size.width == w + 4 and
                s.frame.origin.x > first_frame[0] and s.frame.origin.y > first_frame[1])

    check(await wait_for(moved), "a move and resize by tmux moves and resizes the float")
    tab = await tmux_tab()
    check(tab.floating_sessions[0].session_id == float_session.session_id,
          "the float keeps its session")

    # A float with no border has no room for a title bar, so it loses it and keeps its grid.
    bordered = tab.floating_sessions[0]
    bordered_height = bordered.frame.size.height
    bordered_grid = (bordered.grid_size.width, bordered.grid_size.height)
    tmux("set", "-p", "-t", float_id, "pane-border-lines", "none")

    async def float_height(predicate):
        tab = await tmux_tab()
        if not tab or not tab.floating_sessions:
            return False
        s = tab.floating_sessions[0]
        return (s.grid_size.width, s.grid_size.height) == bordered_grid and predicate(s.frame.size.height)

    check(await wait_for(lambda: float_height(lambda h: h < bordered_height)),
          "a float with pane-border-lines none loses its title bar and keeps its grid")
    tmux("set", "-p", "-u", "-t", float_id, "pane-border-lines")
    check(await wait_for(lambda: float_height(lambda h: h == bordered_height)),
          "it gets its title bar back with a border")

    # A tiled pane becomes floating and keeps its session.
    tiled_id = panes[0]
    tiled_guid = None
    for s in tab.sessions:
        if await s.async_get_variable("tmuxWindowPane") == int(tiled_id[1:]):
            tiled_guid = s.session_id
    tmux("break-pane", "-W", "-s", tiled_id)

    async def two_floats():
        tab = await tmux_tab()
        return tab is not None and len(tab.floating_sessions) == 2

    check(await wait_for(two_floats), "break-pane -W makes a tiled pane a float")
    tab = await tmux_tab()
    check(tiled_guid in [s.session_id for s in tab.floating_sessions],
          "the pane that became a float keeps its session")

    # And back.
    tmux("join-pane", "-s", tiled_id, "-t", tiled_id)

    async def one_float():
        tab = await tmux_tab()
        return tab is not None and len(tab.floating_sessions) == 1

    check(await wait_for(one_float), "join-pane tiles the float again")
    tab = await tmux_tab()
    check(tiled_guid in [s.session_id for s in tab.sessions],
          "the pane that was tiled again keeps its session")

    # Closing the float.
    tmux("kill-pane", "-t", float_id)

    async def no_floats():
        tab = await tmux_tab()
        return tab is not None and len(tab.floating_sessions) == 0

    check(await wait_for(no_floats), "killing the float removes it")

    # Focusing a float raises it with no %layout-change; the layout subscription catches it.
    tmux("new-pane", "-t", "fp", "sleep 600")
    tmux("new-pane", "-t", "fp", "sleep 600")
    floats = [r.split()[0] for r in tmux("list-panes", "-t", "fp", "-F",
                                         "#{pane_id} #{pane_floating_flag}").stdout.splitlines()
              if r.split()[1] == "1"]

    async def floats_in_tab():
        tab = await tmux_tab()
        if not tab:
            return []
        return [str(await s.async_get_variable("tmuxWindowPane")) for s in tab.floating_sessions]

    async def has_two():
        return len(await floats_in_tab()) == 2

    check(await wait_for(has_two), "two floats appear")
    back = (await floats_in_tab())[0]
    tmux("select-pane", "-t", "%" + back)

    async def raised():
        order = await floats_in_tab()
        return bool(order) and order[-1] == back

    check(await wait_for(raised), f"focusing the back float in tmux raises it: {await floats_in_tab()}")
    for pane in floats:
        tmux("kill-pane", "-t", pane)
    check(await wait_for(no_floats), "the floats are gone")

    # iTerm2 drives tmux: create, move, restack and dock through the API.
    tab = await tmux_tab()
    created = await tab.async_create_floating_session()
    created_id = "%" + str(await created.async_get_variable("tmuxWindowPane"))
    check(pane_info(created_id)[4] == 1, f"creating a float in a tmux tab makes tmux float {created_id}")
    before = pane_info(created_id)
    await app.async_refresh()
    created = app.get_session_by_id(created.session_id)
    frame = created.frame
    cell_w = frame.size.width / max(1, created.grid_size.width)
    cell_h = frame.size.height / max(1, created.grid_size.height)
    moved_frame = iterm2.util.Frame(
        iterm2.util.Point(frame.origin.x + 3 * cell_w, frame.origin.y + 1 * cell_h),
        iterm2.util.Size(frame.size.width + 2 * cell_w, frame.size.height))
    await created.async_set_floating_frame(moved_frame)

    async def tmux_moved():
        after = pane_info(created_id)
        return after[2] == before[2] + 3 and after[3] == before[3] + 1 and after[0] == before[0] + 2

    check(await wait_for(tmux_moved), f"setting the frame moves and resizes tmux's pane: {before} -> {pane_info(created_id)}")

    tmux("new-pane", "-t", "fp", "sleep 600")
    await asyncio.sleep(1)

    def front_float():
        rows = tmux("list-panes", "-t", "fp", "-F", "#{pane_id} #{pane_floating_flag} #{pane_z}").stdout.split("\n")
        floats = [r.split() for r in rows if r.split() and r.split()[1] == "1"]
        return min(floats, key=lambda r: int(r[2]))[0] if floats else None

    await created.async_bring_to_front()
    check(await wait_for(lambda: asyncio.sleep(0, result=front_float() == created_id)),
          f"bring to front raises it in tmux: front is {front_float()}")
    await created.async_send_to_back()
    check(await wait_for(lambda: asyncio.sleep(0, result=front_float() != created_id)),
          f"send to back lowers it in tmux: front is {front_float()}")

    # Splitting a float in tmux makes another float.
    tab = await tmux_tab()
    floats_before = len(tab.floating_sessions)
    new_session = await created.async_split_pane(vertical=True)
    new_id = "%" + str(await new_session.async_get_variable("tmuxWindowPane"))
    check(pane_info(new_id)[4] == 1, f"splitting a tmux float makes tmux float {new_id}")

    async def one_more_float():
        tab = await tmux_tab()
        return tab is not None and len(tab.floating_sessions) == floats_before + 1

    check(await wait_for(one_more_float), "the new float appears as a float")
    tmux("kill-pane", "-t", new_id)

    await created.async_dock()

    async def docked():
        return pane_info(created_id)[4] == 0

    check(await wait_for(docked), "docking tiles the pane in tmux")

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
