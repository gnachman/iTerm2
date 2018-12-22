Close Tabs to the Right
=======================

This script defines a function that closes tabs to the right of the current tab in the current window. It demonstrates closing tabs and using `asyncio.gather` to run many async functions at once.

You can bind it to a keystroke in **Prefs > Keys** by selecting the action *Invoke Script Function* and giving it the invocation `close_to_the_right()`.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        @iterm2.RPC
        async def close_to_the_right():
            current_tab = app.current_terminal_window.current_tab
            i = app.current_terminal_window.tabs.index(current_tab)
            tabs_to_close=list(app.current_terminal_window.tabs[(i + 1):])
            coros = []
            for tab in tabs_to_close:
                coro = tab.async_close(force=True)
                coros.append(coro)
            await asyncio.gather(*coros)

        await close_to_the_right.async_register(connection)

    iterm2.run_forever(main)


