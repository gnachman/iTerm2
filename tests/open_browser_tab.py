#!/usr/bin/env python3
"""Open a new tab that uses iTerm2's web browser feature and navigate it to a URL.

Run with:
    python3 open_browser_tab.py [URL]

If URL is omitted, https://example.com/ is used.
"""

import sys
import iterm2


async def main(connection):
    url = sys.argv[1] if len(sys.argv) > 1 else "https://example.com/"

    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is None:
        window = await iterm2.Window.async_create(connection)

    customizations = iterm2.LocalWriteOnlyProfile()
    customizations.set_use_custom_command("Browser")

    tab = await window.async_create_tab(profile_customizations=customizations)
    if tab is None:
        print("Failed to create browser tab.", file=sys.stderr)
        return

    session = tab.current_session
    if session is None:
        print("Browser tab has no session.", file=sys.stderr)
        return

    await session.async_load_url(url)


iterm2.run_until_complete(main)
