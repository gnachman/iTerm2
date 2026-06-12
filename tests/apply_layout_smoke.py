#!/usr/bin/env python3
"""
Manual smoke test for App.async_apply_layout.

Run against a debug iTerm2 build that has at least one window with two
or more split panes already open.

Usage:
    1. Start iTerm2 (e.g. `make run`)
    2. Open a window, split it vertically once (so you have 2 panes)
    3. Run this script: python3 tests/apply_layout_smoke.py
    4. Watch the panes swap, then unswap, then rearrange.
"""

import asyncio
import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    if app is None:
        print("No app")
        return

    window = app.current_terminal_window
    if window is None:
        print("No current window")
        return

    tab = window.current_tab
    if tab is None or len(tab.sessions) < 2:
        print("Open a tab with at least 2 panes first.")
        return

    a = tab.sessions[0].session_id
    b = tab.sessions[1].session_id
    tab_id = tab.tab_id

    print(f"Tab {tab_id}: sessions a={a[:8]} b={b[:8]}")

    # 1. Swap panes
    print("Step 1: swap panes…")
    swap_spec = {
        "tabs": [{
            "tab_id": tab_id,
            "root": {
                "vertical": True,
                "children": [
                    {"session_id": b},
                    {"session_id": a},
                ],
            },
        }],
    }
    await app.async_apply_layout(swap_spec)
    print("Swapped.")
    await asyncio.sleep(2)

    # 2. Swap back
    print("Step 2: swap back…")
    swap_back_spec = {
        "tabs": [{
            "tab_id": tab_id,
            "root": {
                "vertical": True,
                "children": [
                    {"session_id": a},
                    {"session_id": b},
                ],
            },
        }],
    }
    await app.async_apply_layout(swap_back_spec)
    print("Done.")


if __name__ == "__main__":
    iterm2.run_until_complete(main)
