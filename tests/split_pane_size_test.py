#!/usr/bin/env python3
"""Manual end-to-end test for set_split_pane_size and browser pane layout.

Run against a dev build launched with its own suite, never the iTerm2 you work in:
    IT2_SUITE=claude-test IT2_APP_PATH=/path/to/iTerm2.app \
    PYTHONPATH=api/library/python/iterm2 python3 tests/split_pane_size_test.py [mode]

Modes:
  resize   (default) Split a terminal session beside a browser session, then resize the
           browser pane many times with Session.async_set_split_pane_size and check each
           result, that the window keeps its size, and that the app survives.
  layout   Set the browser pane's preferred_size (in points, as a browser grid is) and
           call Tab.async_update_layout(). Before the fix this scaled the browser pane by
           the profile's font cell size, and 1600x1200 crashed the app.

Prints one PASS/FAIL line per check and exits nonzero on any failure.
"""
import asyncio
import sys

import iterm2

MODE = sys.argv[1] if len(sys.argv) > 1 else "resize"
URL = "https://example.com/"
failures = []


def check(name, ok, detail=""):
    print(("PASS" if ok else "FAIL"), name, detail)
    if not ok:
        failures.append(name)


async def frame_of(app, session_id):
    await app.async_refresh()
    session = app.get_session_by_id(session_id)
    return session.frame


async def setup(connection):
    app = await iterm2.async_get_app(connection)
    window = await iterm2.Window.async_create(connection)
    await asyncio.sleep(1)
    # Wide enough that every size in the resize sequence fits beside the terminal.
    frame = await window.async_get_frame()
    await window.async_set_frame(iterm2.util.Frame(frame.origin, iterm2.util.Size(1200, 700)))
    await asyncio.sleep(0.5)
    terminal = window.current_tab.current_session
    profile = iterm2.LocalWriteOnlyProfile()
    profile._simple_set("Custom Command", "Browser")
    profile._simple_set("Initial URL", URL)
    browser = await terminal.async_split_pane(vertical=True, profile_customizations=profile)
    await asyncio.sleep(2)
    return app, window, terminal, browser


async def resize(connection):
    app, window, terminal, browser = await setup(connection)
    window_frame = await window.async_get_frame()
    total = (await frame_of(app, terminal.session_id)).size.width + (await frame_of(app, browser.session_id)).size.width
    print("window", window_frame.size.width, "x", window_frame.size.height, "panes total width", total)
    for i, target in enumerate([395, 600, 395, 450, 395, 700, 395, 500, 395, 395]):
        result = await browser.async_set_split_pane_size(width=target)
        actual = (await frame_of(app, browser.session_id)).size.width
        check(f"resize #{i} browser width {target}", abs(actual - target) <= 1,
              f"result={result} frame={actual}")
    # The terminal pane is the one on the left; resizing it moves the same divider.
    result = await terminal.async_set_split_pane_size(width=total - 395 - 1)
    browser_width = (await frame_of(app, browser.session_id)).size.width
    check("resize terminal so browser is ~395", abs(browser_width - 395) <= 2,
          f"result={result} browser={browser_width}")
    # Below the browser minimum (395) clamps instead of squeezing.
    await browser.async_set_split_pane_size(width=100)
    browser_width = (await frame_of(app, browser.session_id)).size.width
    check("minimum width respected", browser_width >= 394, f"browser={browser_width}")
    # A width wider than the window leaves the terminal its minimum.
    await browser.async_set_split_pane_size(width=100000)
    await app.async_refresh()
    terminal_cols = app.get_session_by_id(terminal.session_id).grid_size.width
    check("terminal keeps at least its minimum columns", terminal_cols >= 2, f"columns={terminal_cols}")
    try:
        await browser.async_set_split_pane_size(height=200)
        check("no horizontal divider is an error", False, "call succeeded")
    except iterm2.rpc.RPCException as e:
        check("no horizontal divider is an error", True, str(e)[:80])
    # Width and height together: the missing height divider fails the call before the
    # width divider moves.
    await browser.async_set_split_pane_size(width=395)
    try:
        await browser.async_set_split_pane_size(width=500, height=200)
        check("width+height with no horizontal divider is an error", False, "call succeeded")
    except iterm2.rpc.RPCException:
        width_after = (await frame_of(app, browser.session_id)).size.width
        check("a failed call changes nothing", abs(width_after - 395) <= 1, f"browser={width_after}")
    after = await window.async_get_frame()
    check("window size unchanged",
          (after.size.width, after.size.height) == (window_frame.size.width, window_frame.size.height),
          f"before={window_frame.size.width}x{window_frame.size.height} after={after.size.width}x{after.size.height}")
    await browser.async_set_split_pane_size(width=395)
    check("app still answers", (await frame_of(app, browser.session_id)) is not None)


async def layout(connection):
    app, window, terminal, browser = await setup(connection)
    before = await window.async_get_frame()
    # 395 is what detail-pane asked for; 1600x1200 is the input that crashed the
    # unfixed build (a browser grid scaled by the font overflowed DVR's int length).
    for width, height in [(395, None), (1600, 1200), (395, None)]:
        await app.async_refresh()
        tab = app.get_session_by_id(browser.session_id).tab
        for session in tab.sessions:
            if session.session_id == browser.session_id:
                session.preferred_size = iterm2.util.Size(width, height or session.grid_size.height)
        await tab.async_update_layout()
        await asyncio.sleep(1)
        browser_width = (await frame_of(app, browser.session_id)).size.width
        after = await window.async_get_frame()
        print("asked", width, "window", before.size.width, "->", after.size.width, "browser frame", browser_width)
        # Scaled by a font cell (about 7 points) a 395 grid would be ~2800 points wide.
        check(f"browser {width} is in points, not font cells", browser_width <= max(width, 395) + 120,
              f"frame={browser_width}")
    check("app survives the input that used to crash it", (await frame_of(app, browser.session_id)) is not None)


async def main(connection):
    await {"resize": resize, "layout": layout}[MODE](connection)
    print("RESULT", "FAIL" if failures else "PASS", failures)


iterm2.run_until_complete(main)
sys.exit(1 if failures else 0)
