#!/usr/bin/env python3

import asyncio
import iterm2
import sys
# To install packages from PyPI, use this command, changing package_name to the package you
# wish to install:
#   "$$PYTHON_BIN$$/pip3" install package_name

async def main(connection, argv):
    # Your code goes here. Here's a bit of example code that adds a tab to the current window:
    a = await iterm2.app.async_get_app(connection)
    w = await a.async.get_key_window()
    if w is not None:
        await w.async_create_tab()
    else:
        # You can view this message in the script console. Open the script console before running
        # the script.
        print("No current window")

if __name__ == "__main__":
    iterm2.connection.Connection().run(main, sys.argv)
