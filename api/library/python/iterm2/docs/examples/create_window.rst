Create Window — Custom Escape Sequence
======================================

This demonstrates handling a custom escape sequence to perform an action. In
this case, the action is to create a new window. This script is meant to be a
starting point for developing your own custom escape sequence handler.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
	app = await iterm2.async_get_app(connection)

	async def on_custom_esc(connection, notification):
	    print("Received a custom escape sequence")
	    if notification.sender_identity == "shared-secret":
		if notification.payload == "create-window":
		    await app.Window.async_create()

	await iterm2.notifications.async_subscribe_to_custom_escape_sequence_notification(connection, on_custom_esc)

	await connection.async_dispatch_until_future(asyncio.Future())

    iterm2.run(main)

To run the script, use:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The *shared-secret* string is used to prevent untrusted code from invoking your
function. For example, if you `cat` a text file, it could include escape
sequences.
