#!/usr/bin/env python3
"""Automated check of the tab pinning Python API (Tab.pinned, async_set_pinned).

Creates its own window with four tabs, so your other windows are untouched,
and closes it at the end. Prints one line per check and a final
"RESULT PASS" or "RESULT FAIL [...]".

Needs an iTerm2 build advertising protocol >= 1.21 with the Python API
enabled, and this checkout's iterm2 module on PYTHONPATH.
"""

import asyncio

import iterm2

failures = []


def check(label, ok):
    print("{} {}".format("ok  " if ok else "FAIL", label))
    if not ok:
        failures.append(label)


async def window_with_id(connection, window_id):
    app = await iterm2.async_get_app(connection)
    return app.get_window_by_id(window_id)


def tab_in(window, tab_id):
    return next(t for t in window.tabs if t.tab_id == tab_id)


def index_of(window, tab_id):
    return [t.tab_id for t in window.tabs].index(tab_id)


async def main(connection):
    # Creating the App installs the delegates Window and Tab methods rely on.
    await iterm2.async_get_app(connection)
    window = await iterm2.Window.async_create(connection)
    window_id = window.window_id
    for _ in range(3):
        await window.async_create_tab()
    window = await window_with_id(connection, window_id)
    tab_ids = [t.tab_id for t in window.tabs]
    check("window has four unpinned tabs",
          len(tab_ids) == 4 and not any(t.pinned for t in window.tabs))

    try:
        # Pin the last tab: it moves to the far left.
        last = window.tabs[-1]
        await last.async_set_pinned(True)
        window = await window_with_id(connection, window_id)
        tab = tab_in(window, last.tab_id)
        check("pinned tab reports pinned=True", tab.pinned is True)
        check("pinned tab sits at index 0", index_of(window, last.tab_id) == 0)

        # Pin another: it goes after the existing pinned tab, not before it.
        third = window.tabs[-1]
        await third.async_set_pinned(True)
        window = await window_with_id(connection, window_id)
        check("second pinned tab lands at index 1",
              index_of(window, third.tab_id) == 1 and
              index_of(window, last.tab_id) == 0)

        # Unpin both.
        await tab_in(window, last.tab_id).async_set_pinned(False)
        await tab_in(window, third.tab_id).async_set_pinned(False)
        window = await window_with_id(connection, window_id)
        check("unpinned tabs report pinned=False",
              not tab_in(window, last.tab_id).pinned and
              not tab_in(window, third.tab_id).pinned)

        # A grouped tab takes its whole group with it, like the menu item.
        members = window.tabs[-2:]
        await window.async_create_tab_group("pin-test", members)
        window = await window_with_id(connection, window_id)
        await tab_in(window, members[1].tab_id).async_set_pinned(True)
        window = await window_with_id(connection, window_id)
        check("pinning one group member pins the whole group",
              all(tab_in(window, m.tab_id).pinned for m in members))
        check("pinned group occupies the leftmost slots",
              sorted(index_of(window, m.tab_id) for m in members) == [0, 1])
        await tab_in(window, members[0].tab_id).async_set_pinned(False)
        window = await window_with_id(connection, window_id)
        check("unpinning one group member unpins the whole group",
              not any(tab_in(window, m.tab_id).pinned for m in members))
    finally:
        window = await window_with_id(connection, window_id)
        if window:
            await window.async_close(force=True)

    print("RESULT {} {}".format("FAIL" if failures else "PASS", failures))


iterm2.run_until_complete(main)
