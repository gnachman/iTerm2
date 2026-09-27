#!/usr/bin/env python3
"""Interactive exercise for the tab group Python API.

To avoid disturbing your existing windows, this script creates its OWN new
window on startup and does everything inside it. Every operation targets only
that window; your other windows are never touched. On quit you can close the
test window or leave it open.

Run it with the wrapper so it uses this checkout's iterm2 module:

    tests/run_tab_group_test.sh

A debug iTerm2 build advertising the tab-group capability (protocol >= 1.19)
must already be running with the Python API enabled.
"""

import iterm2

# A few named colors to pick from when creating or recoloring a group.
PALETTE = {
    "red": iterm2.Color(255, 59, 48),
    "orange": iterm2.Color(255, 149, 0),
    "yellow": iterm2.Color(255, 204, 0),
    "green": iterm2.Color(52, 199, 89),
    "blue": iterm2.Color(0, 122, 255),
    "purple": iterm2.Color(175, 82, 222),
    "pink": iterm2.Color(255, 45, 85),
}


class TestWindow:
    """Holds the id of the window we created and re-fetches its live state."""

    def __init__(self, connection, window_id):
        self.connection = connection
        self.window_id = window_id
        self.app = None

    async def refresh(self):
        """Re-reads app state so tab/group changes are reflected."""
        self.app = await iterm2.async_get_app(self.connection)
        return self.window

    @property
    def window(self):
        if self.app is None:
            return None
        for window in self.app.windows:
            if window.window_id == self.window_id:
                return window
        return None


def color_str(color):
    if color is None:
        return "no color"
    return "{} (rgb {},{},{})".format(
        color.hex, round(color.red), round(color.green), round(color.blue))


async def show_state(test):
    window = await test.refresh()
    if window is None:
        print("The test window is gone. Quit and start over.")
        return

    print("\n=== Test window {} ===".format(window.window_id))
    print("Tabs (in tab-bar order):")
    for i, tab in enumerate(window.tabs):
        title = tab.current_session.name if tab.current_session else "(?)"
        group = tab.tab_group
        if group is None:
            membership = "ungrouped"
        else:
            membership = "group {}[{}]{}".format(
                repr(group.name),
                group.group_id[:8],
                " (collapsed)" if group.collapsed else "")
        print("  [{}] tab {} {!r:>16}  {}".format(
            i, tab.tab_id, title, membership))

    groups = window.tab_groups
    print("Tab groups in this window:")
    if not groups:
        print("  (none)")
    for gi, group in enumerate(groups):
        print("  ({}) {!r}  id={}  {}  {}".format(
            gi,
            group.name,
            group.group_id[:8],
            color_str(group.color),
            "collapsed" if group.collapsed else "expanded"))


def pick_tabs(window):
    """Prompt for space-separated tab indices; returns a list of Tab."""
    raw = input("Tab indices (e.g. '0 1 2'): ").split()
    tabs = []
    for token in raw:
        try:
            tabs.append(window.tabs[int(token)])
        except (ValueError, IndexError):
            print("Bad index: {}".format(token))
            return None
    return tabs


def pick_group(window):
    """Prompt for a group index into window.tab_groups; returns a TabGroup."""
    groups = window.tab_groups
    if not groups:
        print("This window has no tab groups yet.")
        return None
    try:
        gi = int(input("Group index: "))
        return groups[gi]
    except (ValueError, IndexError):
        print("Bad group index.")
        return None


def pick_color():
    """Prompt for a palette color name; returns a Color or None (auto)."""
    print("Colors: {} (blank = let iTerm2 choose)".format(
        ", ".join(PALETTE.keys())))
    name = input("Color: ").strip().lower()
    if not name:
        return None
    if name not in PALETTE:
        print("Unknown color; letting iTerm2 choose.")
        return None
    return PALETTE[name]


async def do_create(test):
    window = await test.refresh()
    tabs = pick_tabs(window)
    if not tabs:
        return
    name = input("Group name: ").strip() or "Group"
    color = pick_color()
    group = await window.async_create_tab_group(name, tabs, color)
    print("Created group {!r} id={}".format(group.name, group.group_id[:8]))


async def do_add(test):
    window = await test.refresh()
    tabs = pick_tabs(window)
    if not tabs or len(tabs) != 1:
        print("Pick exactly one tab to add.")
        return
    group = pick_group(window)
    if group is None:
        return
    await tabs[0].async_add_to_tab_group(group)
    print("Added tab {} to group {!r}.".format(tabs[0].tab_id, group.name))


async def do_remove(test):
    window = await test.refresh()
    tabs = pick_tabs(window)
    if not tabs or len(tabs) != 1:
        print("Pick exactly one tab to remove.")
        return
    await tabs[0].async_remove_from_tab_group()
    print("Removed tab {} from its group.".format(tabs[0].tab_id))


async def do_rename(test):
    window = await test.refresh()
    group = pick_group(window)
    if group is None:
        return
    name = input("New name: ").strip()
    await group.async_set_name(name)
    print("Renamed group to {!r}.".format(name))


async def do_recolor(test):
    window = await test.refresh()
    group = pick_group(window)
    if group is None:
        return
    color = pick_color()
    if color is None:
        print("No color chosen; nothing to do.")
        return
    await group.async_set_color(color)
    print("Recolored group to {}.".format(color.hex))


async def do_collapse(test):
    window = await test.refresh()
    group = pick_group(window)
    if group is None:
        return
    want = input("Collapse or expand? [c/e]: ").strip().lower()
    collapsed = want.startswith("c")
    result = await group.async_set_collapsed(collapsed)
    if result != collapsed:
        print("iTerm2 refused (a whole-window group can't collapse). "
              "State is now {}.".format("collapsed" if result else "expanded"))
    else:
        print("Group is now {}.".format(
            "collapsed" if result else "expanded"))


async def do_add_tab(test):
    window = await test.refresh()
    await window.async_create_tab()
    print("Added a tab to the test window.")


async def main(connection):
    # Fetch the app first: this installs the Window/Tab delegates that
    # window.async_create_tab (and tab.window) rely on.
    await iterm2.async_get_app(connection)

    print("Creating a new window for testing (your other windows are safe)...")
    window = await iterm2.Window.async_create(connection)
    if window is None:
        print("Could not create a window.")
        return
    test = TestWindow(connection, window.window_id)

    # Give ourselves a few tabs to play with.
    for _ in range(3):
        await window.async_create_tab()
    print("Test window {} created with 4 tabs.".format(window.window_id))

    while True:
        print("\n=== Tab Group Test ===")
        print("  1. Show window + groups")
        print("  2. Create a group from tabs")
        print("  3. Add a tab to an existing group")
        print("  4. Remove a tab from its group")
        print("  5. Rename a group")
        print("  6. Recolor a group")
        print("  7. Collapse / expand a group")
        print("  8. Add another tab to the window")
        print("  c. Close the test window and quit")
        print("  q. Quit (leave the test window open)")

        choice = input("\nChoice: ").strip().lower()
        try:
            if choice == "q":
                break
            elif choice == "c":
                target = await test.refresh()
                if target is not None:
                    await target.async_close(force=True)
                    print("Closed the test window.")
                break
            elif choice == "1":
                await show_state(test)
            elif choice == "2":
                await do_create(test)
            elif choice == "3":
                await do_add(test)
            elif choice == "4":
                await do_remove(test)
            elif choice == "5":
                await do_rename(test)
            elif choice == "6":
                await do_recolor(test)
            elif choice == "7":
                await do_collapse(test)
            elif choice == "8":
                await do_add_tab(test)
            else:
                print("Unknown choice.")
        except Exception as exc:  # noqa: BLE001 - surface any RPC error and continue
            print("Error: {}".format(exc))


iterm2.run_until_complete(main)
