#!/usr/bin/env python3

import iterm2
import sys
# This script was created with the "basic" environment which does not support adding dependencies
# with pip.

async def main(connection, argv):
    # Your code goes here. Here's a bit of example code that adds a tab to the current window:
    app = await iterm2.async_get_app(connection)
    window = app.current_terminal_window
    if window is not None:
        await window.async_create_tab()
    else:
        # You can view this message in the script console. Open the script console before running
        # the script.
        print("No current window")

if __name__ == "__main__":
    iterm2.Connection().run(main, sys.argv)
