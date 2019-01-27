.. _cls_example:

Clear All Sessions
==================

The script clears the buffer including scrollback history from all sessions.

You can bind it to a keystroke in **Prefs > Keys** by selecting the action *Invoke Script Function* and giving it the invocation `clear_all_sessions()`.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2
    import time

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        @iterm2.RPC
        async def clear_all_sessions():
            code = b'\x1b' + b']1337;ClearScrollback' + b'\x07'
            for window in app.terminal_windows:
                for tab in window.tabs:
                    for session in tab.sessions:
                        await session.async_inject(code)

        await clear_all_sessions.async_register(connection)

    iterm2.run_forever(main)

:Download:`Download<cls.its>`
