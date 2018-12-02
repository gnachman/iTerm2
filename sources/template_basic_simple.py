#!/usr/bin/env python3.7

import iterm2
# This script was created with the "basic" environment which does not support adding dependencies
# with pip.

async def main(connection):
    # Your code goes here. Here's a bit of example code that adds a tab to the current window:
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is not None:
        await window.async_create_tab()
    else:
        # You can view this message in the script console.
        print("No current window")

iterm2.run_until_complete(main)
