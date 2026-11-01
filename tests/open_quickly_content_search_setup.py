#!/usr/bin/env python3
# Manual test setup for Open Quickly's session contents search ("/g").
#
# Opens a window with many tabs, each with a few thousand lines of scrollback.
# Every tab gets a unique word, and exactly one tab gets the needle phrase, so
# typing "/g <needle>" in Open Quickly should list exactly that tab.
#
# Usage: open_quickly_content_search_setup.py [tabs] [lines-per-tab] [needle]
import asyncio
import sys

import iterm2

TABS = int(sys.argv[1]) if len(sys.argv) > 1 else 32
LINES = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
NEEDLE = sys.argv[3] if len(sys.argv) > 3 else "quokka-scrollback-needle"
NEEDLE_TAB = TABS // 2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    window = await iterm2.Window.async_create(connection)
    for _ in range(TABS - 1):
        await window.async_create_tab()
    # Re-read the window: tabs created through the API are not all reflected in
    # the object returned by async_create.
    await app.async_refresh()
    tabs = app.get_window_by_id(window.window_id).tabs
    for i, tab in enumerate(tabs):
        session = tab.current_session
        await tab.async_set_title(f"tab {i}")
        extra = f"; echo 'the {NEEDLE} is here'" if i == NEEDLE_TAB else ""
        await session.async_send_text(
            f"clear; for i in $(seq {LINES}); do echo \"filler line $i in tab {i} lorem ipsum dolor\"; done; "
            f"echo unique-word-{i}{extra}\n")
    await tabs[0].async_activate()
    print(f"window {window.window_id}: {len(tabs)} tabs; needle in tab {NEEDLE_TAB} "
          f"session {tabs[NEEDLE_TAB].current_session.session_id}")

iterm2.run_until_complete(main)
