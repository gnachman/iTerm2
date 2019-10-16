
.. _app_tab_color_example:

Set Tab Color from Current App
==============================

This script sets the tab color based on the current app.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2
    import os
    import random

    colors = { "vi": (255, 255, 255), "emacs": (255, 0, 0) }

    async def SetTabColor(connection, session, color):
	change = iterm2.LocalWriteOnlyProfile()
	if color:
	    change.set_tab_color(color)
	    change.set_use_tab_color(True)
	else:
	    change.set_use_tab_color(False)
	await session.async_set_profile_properties(change)

    async def UpdateTabColor(connection, session, command):
	try:
	    parts = command.split(" ")
	    command = os.path.basename(os.path.normpath(parts[0]))
	    r,g,b = colors[command]
	    color = iterm2.Color(r, g, b)
	    await SetTabColor(connection, session, color)
	except Exception as e:
	    print(e)

    async def main(connection):
	app = await iterm2.async_get_app(connection)

	async def monitor(session_id):
	    """Run for each session, including existing sessions. Watches for
	    changes to the running commands."""
	    session = app.get_session_by_id(session_id)
	    if not session:
		return
	    alert_task = None
	    modes = [iterm2.PromptMonitor.Mode.COMMAND_END,
		     iterm2.PromptMonitor.Mode.COMMAND_START]
	    async with iterm2.PromptMonitor(
		    connection, session_id, modes=modes) as mon:
		while True:
		    mode, _ = await mon.async_get()
		    if mode == iterm2.PromptMonitor.Mode.COMMAND_START:
			prompt = await iterm2.async_get_last_prompt(connection, session_id)
			await UpdateTabColor(connection, session, prompt.command)
		    else:
			await SetTabColor(connection, session, None)

	await iterm2.EachSessionOnceMonitor.async_foreach_session_create_task(
		app, monitor)

    iterm2.run_forever(main)

:Download:`Download<app_tab_color.its>`
