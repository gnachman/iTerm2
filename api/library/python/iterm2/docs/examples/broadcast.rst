Asymmetric Broadcast Input
==========================

This script creates four split panes and broadcasts input from the bottom left one to the other three. If a pane other than the bottom-left one has focus, input to it does not get broadcast--it just goes to that pane.

This demonstrates:

* Using a :class:`KeystrokeReader` reader to receive keystrokes
* Using `patterns_to_ignore` to prevent iTerm2 from handling certain keystrokes
* Using :meth:`Session.async_send_text` to send fake keystrokes to a session

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
	app = await iterm2.async_get_app(connection)

	# Create four split panes and make the bottom left one active.
	bottomLeft = app.current_terminal_window.current_tab.current_session
	bottomRight = await bottomLeft.async_split_pane(vertical=True)
	topLeft = await bottomLeft.async_split_pane(vertical=False, before=True)
	topRight = await bottomRight.async_split_pane(vertical=False, before=True)
	await bottomLeft.async_activate()
	broadcast_to = [ topLeft, topRight, bottomRight ]

	async def async_handle_keystroke(notification):
	    """Called on each keystroke with iterm2.api_pb2.KeystrokeNotification"""
	    if notification.keyCode == 0x35:
		# User pressed escape. Terminate script.
                # A list of keycodes is here: https://stackoverflow.com/a/16125341/321984
		return True
	    for session in broadcast_to:
		await session.async_send_text(notification.characters)
	    return False

	# Construct a pattern that matches all keystrokes except those with a Command modifier.
	# This prevents iTerm2 from handling them when the bottomLeft session has keyboard focus.
	pattern = iterm2.KeystrokePattern()
	pattern.keycodes.extend(range(0, 65536))
	pattern.forbidden_modifiers.extend([iterm2.MODIFIER_COMMAND])

	# This will block until async_handle_keystroke returns True.
	async with bottomLeft.get_keystroke_reader(patterns_to_ignore=[pattern]) as reader:
	    done = False
	    while not done:
		for keystroke in await reader.async_get():
		    done = await async_handle_keystroke(keystroke)
		    if done:
			break

    iterm2.run(main)

