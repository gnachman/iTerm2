#!/usr/bin/env python3
"""Non-interactive check of nested tab groups through the Python API.

Run it against a debug build with this checkout's iterm2 module on PYTHONPATH:

    tests/nested_tab_group_test.py setup      # new window: parent group with a sub-group
    tests/nested_tab_group_test.py check      # verify the hierarchy and tab order
    tests/nested_tab_group_test.py collapse NAME 1|0
    tests/nested_tab_group_test.py width POINTS  # resize the test window
    tests/nested_tab_group_test.py quit          # Quit (saves state for restoration)
    tests/nested_tab_group_test.py save NAME  # save the test window as an arrangement
    tests/nested_tab_group_test.py restore NAME

`setup` builds, in a window of its own:

    [loner] [Idle: idle-1 [Parakeet: pk-1 pk-2] idle-2]

Every mode ends with a line "RESULT PASS" or "RESULT FAIL <reasons>".
"""

import sys

import iterm2

PARENT = "Idle"
CHILD = "Parakeet"


def tab_title(tab):
    return tab.current_session.name if tab.current_session else "?"


async def find_test_window(app):
    for window in app.terminal_windows:
        names = {group.name for group in window.tab_groups}
        if PARENT in names:
            return window
    return None


def describe(window):
    rows = []
    for tab in window.tabs:
        group = tab.tab_group
        parent = tab.tab_group_parent
        rows.append("%-10s group=%-9s parent=%-5s collapsed=%s/%s" % (
            tab_title(tab),
            group.name if group else "-",
            parent.name if parent else "-",
            group.collapsed if group else "-",
            parent.collapsed if parent else "-"))
    return "\n".join(rows)


def check_hierarchy(window):
    """Returns a list of problems (empty when the hierarchy is right)."""
    problems = []
    groups = {group.name: group for group in window.tab_groups}
    if PARENT not in groups or CHILD not in groups:
        return ["missing groups: %s" % sorted(groups)]
    parent, child = groups[PARENT], groups[CHILD]
    if parent.parent_group_id is not None:
        problems.append("parent has a parent")
    if child.parent_group_id != parent.group_id:
        problems.append("child's parent_group_id %r != %r" % (child.parent_group_id, parent.group_id))
    names = [group.name for group in window.tab_groups]
    if names.index(PARENT) > names.index(CHILD):
        problems.append("tab_groups lists the child before its parent: %s" % names)

    # Contiguity: the parent's tabs (sub-group included) form one run, and the
    # sub-group's tabs form one run inside it.
    def in_parent(tab):
        return ((tab.tab_group and tab.tab_group.group_id == parent.group_id) or
                (tab.tab_group_parent and tab.tab_group_parent.group_id == parent.group_id))

    def in_child(tab):
        return tab.tab_group is not None and tab.tab_group.group_id == child.group_id

    parent_idx = [i for i, tab in enumerate(window.tabs) if in_parent(tab)]
    child_idx = [i for i, tab in enumerate(window.tabs) if in_child(tab)]
    if parent_idx != list(range(parent_idx[0], parent_idx[-1] + 1)):
        problems.append("parent run is not contiguous: %s" % parent_idx)
    if child_idx != list(range(child_idx[0], child_idx[-1] + 1)):
        problems.append("child run is not contiguous: %s" % child_idx)
    if not set(child_idx) <= set(parent_idx):
        problems.append("child run is outside the parent run")
    if len(parent_idx) != 4 or len(child_idx) != 2:
        problems.append("expected 4 tabs in the parent and 2 in the child, got %d/%d" %
                        (len(parent_idx), len(child_idx)))
    return problems


async def new_tab(window, title):
    tab = await window.async_create_tab()
    await tab.current_session.async_set_name(title)
    return tab


async def main(connection):
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    app = await iterm2.async_get_app(connection)
    problems = []

    if mode == "setup":
        window = await iterm2.Window.async_create(connection)
        await window.tabs[0].current_session.async_set_name("loner")
        idle_1 = await new_tab(window, "idle-1")
        pk_1 = await new_tab(window, "pk-1")
        idle_2 = await new_tab(window, "idle-2")
        pk_2 = await new_tab(window, "pk-2")
        await app.async_refresh()
        window = app.get_window_by_id(window.window_id)
        parent = await window.async_create_tab_group(
            PARENT, [idle_1, pk_1, idle_2, pk_2], iterm2.Color(52, 199, 89))
        await window.async_create_tab_group(
            CHILD, [pk_1, pk_2], iterm2.Color(0, 122, 255), parent=parent)
        await app.async_refresh()
        window = app.get_window_by_id(window.window_id)
        problems = check_hierarchy(window)
    elif mode == "collapse":
        name, value = sys.argv[2], sys.argv[3] == "1"
        window = await find_test_window(app)
        group = {g.name: g for g in window.tab_groups}[name]
        state = await group.async_set_collapsed(value)
        print("collapsed(%s) -> %s" % (name, state))
        await app.async_refresh()
        window = app.get_window_by_id(window.window_id)
        group = {g.name: g for g in window.tab_groups}[name]
        if group.collapsed != value:
            problems.append("%s.collapsed is %s, wanted %s" % (name, group.collapsed, value))
        if window.current_tab.tab_group and window.current_tab.tab_group.collapsed:
            problems.append("the active tab is in a collapsed group")
        problems += check_hierarchy(window)
    elif mode == "width":
        window = await find_test_window(app)
        frame = await window.async_get_frame()
        frame.size.width = float(sys.argv[2])
        await window.async_set_frame(frame)
    elif mode == "quit":
        # A real Quit (not a signal) so the window state is saved for restoration.
        await iterm2.MainMenu.async_select_menu_item(
            connection, iterm2.MainMenu.iTerm2.QUIT_ITERM2.value.identifier)
        return
    elif mode == "save":
        window = await find_test_window(app)
        await window.async_save_window_as_arrangement(sys.argv[2])
    elif mode == "restore":
        await iterm2.Arrangement.async_restore(connection, sys.argv[2])
        await app.async_refresh()
        windows = [w for w in app.terminal_windows
                   if PARENT in {g.name for g in w.tab_groups}]
        if not windows:
            problems.append("no restored window has the groups")
        for window in windows:
            problems += check_hierarchy(window)
    else:
        window = await find_test_window(app)
        if window is None:
            problems.append("no window with the test groups")
        else:
            problems = check_hierarchy(window)

    window = await find_test_window(app)
    if window is not None:
        print("window %s" % window.window_id)
        print(describe(window))
    print("RESULT PASS" if not problems else "RESULT FAIL %s" % problems)


iterm2.run_until_complete(main)
