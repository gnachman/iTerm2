#!/usr/bin/env python3
"""Manual end-to-end test for browser_set_toolbar_hidden.

Run against a dev build launched with its own suite, never the iTerm2 you work in:
    IT2_SUITE=claude-test IT2_APP_PATH=/path/to/iTerm2.app \
    PYTHONPATH=api/library/python/iterm2 python3 tests/browser_toolbar_test.py

Opens a browser session beside a terminal session, hides and shows its toolbar, and
checks that the page's innerHeight grows by the toolbar's 44 points and shrinks back.
The page must be allowed to run JavaScript from scripts (the first run asks).
Prints one PASS/FAIL line per check and exits nonzero on any failure.
"""
import asyncio
import sys

import iterm2

URL = "https://example.com/"
failures = []


def check(name, ok, detail=""):
    print(("PASS" if ok else "FAIL"), name, detail)
    if not ok:
        failures.append(name)


async def wait_ready(session, timeout=30):
    for _ in range(timeout * 2):
        try:
            if await session.async_eval_javascript("return document.readyState") == "complete":
                return True
        except Exception:
            pass
        await asyncio.sleep(0.5)
    return False


async def main(connection):
    await iterm2.async_get_app(connection)  # split_pane needs the app's delegate
    window = await iterm2.Window.async_create(connection)
    await asyncio.sleep(1)
    terminal = window.current_tab.current_session
    profile = iterm2.LocalWriteOnlyProfile()
    profile._simple_set("Custom Command", "Browser")
    profile._simple_set("Initial URL", URL)
    browser = await terminal.async_split_pane(vertical=True, profile_customizations=profile)
    print("page ready:", await wait_ready(browser))
    shown = await browser.async_eval_javascript("return window.innerHeight")
    await browser.async_set_browser_toolbar_hidden(True)
    await asyncio.sleep(0.5)
    hidden = await browser.async_eval_javascript("return window.innerHeight")
    check("hiding the toolbar gives the page its 44 points", hidden - shown == 44,
          f"shown={shown} hidden={hidden}")
    await browser.async_set_browser_toolbar_hidden(False)
    await asyncio.sleep(0.5)
    again = await browser.async_eval_javascript("return window.innerHeight")
    check("showing it takes them back", again == shown, f"again={again}")
    try:
        await terminal.async_set_browser_toolbar_hidden(True)
        check("terminal session is rejected", False, "call succeeded")
    except iterm2.rpc.RPCException as e:
        check("terminal session is rejected", True, str(e)[:80])
    print("RESULT", "FAIL" if failures else "PASS", failures)


iterm2.run_until_complete(main)
sys.exit(1 if failures else 0)
