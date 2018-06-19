Clear All Sessions
==================

The script clears the buffer including scrollback history from all sessions.

You can bind it to a keystroke in **Prefs > Keys** by selecting the action *Invoke Script Function* and giving it the invocation `clear_all_sessions()`.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2
    import sys
    import time

    async def main(connection, argv):
	app = await iterm2.async_get_app(connection)

	async def clear_all_sessions():
	    code = b'\x1b' + b']1337;ClearScrollback' + b'\x07'
	    for window in app.terminal_windows:
		for tab in window.tabs:
		    for session in tab.sessions:
			await session.async_inject(code)

	await app.async_register_rpc_handler("clear_all_sessions", clear_all_sessions)

	await connection.async_dispatch_until_future(asyncio.Future())

    if __name__ == "__main__":
	iterm2.Connection().run(main, sys.argv)

