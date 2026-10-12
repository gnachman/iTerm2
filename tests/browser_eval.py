#!/usr/bin/env python3
"""Runs JavaScript in an iTerm2 browser session and prints the result as JSON.

    browser_eval.py [--url URL] [JS]

JS is the body of an async function: it may use await and should return a
value. Without JS, it prints the page's title, URL, and number of links.
Without --url, it uses a browser session that's already open, preferring one in
the frontmost window. With --url, it opens a new browser window on URL first.

The first time JavaScript runs on a site, iTerm2 asks you to allow it.

Use tests/browser_eval.sh to run this against a dev build.
"""
import argparse
import asyncio
import json
import sys

import iterm2

DEFAULT_JS = """
return {
    title: document.title,
    url: location.href,
    links: document.querySelectorAll("a[href]").length,
};
"""


async def open_browser_window(connection, url):
    profile = iterm2.LocalWriteOnlyProfile()
    profile._simple_set("Custom Command", "Browser")
    profile._simple_set("Initial URL", url)
    window = await iterm2.Window.async_create(connection, profile_customizations=profile)
    return window.current_tab.current_session


async def is_browser(session):
    profile = await session.async_get_profile()
    return profile.use_custom_command == "Browser"


async def find_browser_session(connection):
    """Returns a browser session, preferring the frontmost window's, or None."""
    app = await iterm2.async_get_app(connection)
    front = app.current_terminal_window
    windows = ([front] if front else []) + [w for w in app.terminal_windows if w is not front]
    for window in windows:
        for tab in window.tabs:
            for session in tab.sessions:
                if await is_browser(session):
                    return session
    return None


async def wait_for_load(session, timeout=30):
    """Waits for an http(s) page to finish loading. Before the first one commits,
    the session has no page that JavaScript may run in, so the call fails."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        try:
            if await session.async_eval_javascript("return document.readyState") == "complete":
                return
        except iterm2.rpc.RPCException:
            pass
        await asyncio.sleep(0.25)
    raise TimeoutError("The page did not finish loading")


async def main(connection, args):
    if args.url:
        session = await open_browser_window(connection, args.url)
        await wait_for_load(session)
    else:
        session = await find_browser_session(connection)
        if not session:
            sys.exit("No browser session is open. Pass --url to open one.")
    try:
        result = await session.async_eval_javascript(args.js or DEFAULT_JS)
    except iterm2.rpc.RPCException as e:
        sys.exit(f"Failed: {e}")
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run JavaScript in an iTerm2 browser session.")
    parser.add_argument("--url", help="Open a new browser window on this URL first")
    parser.add_argument("js", nargs="?", help="Function body to run; it should return a value")
    parsed = parser.parse_args()
    iterm2.run_until_complete(lambda connection: main(connection, parsed))
