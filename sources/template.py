#!/usr/bin/env python3

import asyncio
import iterm2
import sys
import traceback

async def main(connection, argv):
    # Your code goes here. Here's an example of how to create a new window:
    await iterm2.window.Window.create(connection)

if __name__ == "__main__":
    iterm2.connection.Connection().run(main, sys.argv)
