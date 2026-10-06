#!/usr/bin/env python3
# Close every window in the dev instance and open one fresh window. Prints its window ID.
# Run it through devapi.sh so it reaches the dev instance:
#   tests/floating_panes/devapi.sh tests/floating_panes/reset_windows.py
import iterm2


async def main(connection):
    app = await iterm2.async_get_app(connection)
    old = list(app.windows)
    window = await iterm2.Window.async_create(connection)
    for w in old:
        await w.async_close(force=True)
    print(window.window_id)

iterm2.run_until_complete(main)
