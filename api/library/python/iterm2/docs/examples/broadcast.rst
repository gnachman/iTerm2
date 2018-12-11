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

        async def async_handle_keystroke(keystroke):
            if keystroke.keycode == iterm2.Keycode.ESCAPE:
                # User pressed escape. Terminate script.
                return True
            for session in broadcast_to:
                await session.async_send_text(keystroke.characters)
            return False

        # Construct a pattern that matches all keystrokes except those with a Command modifier.
        # This prevents iTerm2 from handling them when the bottomLeft session has keyboard focus.
        pattern = iterm2.KeystrokePattern()
        pattern.keycodes = [keycode for keycode in iterm2.Keycode]
        pattern.forbidden_modifiers = [iterm2.Modifier.COMMAND]

        future = asyncio.Future()

        # Swallow all keystrokes matching the pattern
        async def filter_all_keystrokes():
          async with iterm2.KeystrokeFilter(connection, [pattern], bottomLeft.session_id) as mon:
              await asyncio.wait([future])

        task = asyncio.create_task(filter_all_keystrokes())


        # This will block until async_handle_keystroke returns True.
        async with iterm2.KeystrokeMonitor(connection, bottomLeft.session_id) as mon:
            done = False
            while not done:
                keystroke = await mon.async_get()
                done = await async_handle_keystroke(keystroke)
                if done:
                    break
            future.set_result(True)

        await task

    iterm2.run_until_complete(main)
