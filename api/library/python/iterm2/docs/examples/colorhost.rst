Per-Host Colors
===============

This script sets the color of a session based on the current hostname. For it to work, iTerm2 must know the current hostname. You can do that either by installing Shell Integration or by defining triggers that detect the hostname. More information on that is available here: https://www.iterm2.com/documentation-shell-integration.html

Edit the `colormap` variable to specify the hostname to color preset mapping you prefer.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    colormap = { "example.com": "Dark Background",
		 "Georges-iMac.local": "Light Background" }

    async def SetPresetInSession(connection, session, preset_name):
	"""Change the colors in session to the color preset named `preset_name`.
	Does not modify the underlying profile."""
	preset = await iterm2.ColorPreset.async_get(connection, preset_name)
	if not preset:
	    return
	profile = await session.async_get_profile()
	if not profile:
	    return
	await profile.async_set_color_preset(preset)

    async def MonitorSession(connection, session):
	"""Called when a new session is created."""
	hostname = await session.async_get_variable("session.hostname")
	if hostname in colormap:
	    await SetPresetInSession(connection, session, colormap[hostname])

	async with iterm2.VariableMonitor(
		connection,
		iterm2.VariableScopes.SESSION,
		"session.hostname",
		session.session_id) as mon:
	    while True:
		hostname = await mon.async_get()
		if hostname in colormap:
		    await SetPresetInSession(
			    connection,
			    session,
			    colormap[hostname])

    async def main(connection):
	# Monitor existing sessions
	app = await iterm2.async_get_app(connection)
	for window in app.terminal_windows:
	    for tab in window.tabs:
		for session in tab.sessions:
		    asyncio.create_task(MonitorSession(connection, session))

	# When new sessions are created, monitor them, too.
	async with iterm2.NewSessionMonitor(connection) as mon:
	    while True:
		session_id = await mon.async_get()
		asyncio.create_task(MonitorSession(connection, app.get_session_by_id(session_id)))

    iterm2.run_forever(main)
