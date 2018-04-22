#!/usr/bin/env python3.6

from __future__ import print_function

import asyncio
import iterm2
import sys
import time
import traceback

future = None

async def on_custom_esc(connection, notif):
  global future
  print(notif)
  future.set_result(notif)

async def program(connection):
  try:
    h = await iterm2.hierarchy.Hierarchy.construct(connection)
    for s in h.windows[0].tabs[0].get_sessions():
      await iterm2.notifications.subscribe_to_custom_escape_sequence_notification(connection, on_custom_esc, s.session_id)
    while True:
      global future
      future = asyncio.Future()
      await connection.dispatch_until_future(future)
  except Exception as e:
    print(traceback.format_exc())

def main(argv):
    c = iterm2.connection.Connection()
    c.run(program)

if __name__ == "__main__":
  try:
    main(sys.argv)
  except:
    sys.exit(1)
