Escape Key Indicator
====================

This script defines a custom status bar control that shows an indicator briefly after you press the escape key. This is useful if you are afflicted with a touch bar.

This script demonstrates a custom status bar component, a keyboard monitor, and using user-defined variables to make the keyboard monitor elicit a change in the status bar. It also demonstrates using asyncio tasks to perform an action after a delay, as well as how to cancel asyncio tasks.

After starting this script, navigate to **Preferences > Profiles > Session**. Turn on **Status Bar Enabled** and select **Configure Status Bar**. Drag the **Esc Key Indicator** component into the bottom section.

This script is a long-running daemon since it must continually update the status bar. As such, it should go in the AutoLaunch folder.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    counter = 0

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        tasks = {}

        component = iterm2.StatusBarComponent(
            name="EscIndicator",
            short_description="Esc Key Indicator",
            detailed_description="Shows a visual indicator when the esc key is pressed",
            knobs=[],
            exemplar="[esc]",
            update_cadence=None,
            identifier="com.iterm2.escindicator")

        async def reset(session):
            await asyncio.sleep(2)
            await session.async_set_variable("user.showEscIndicator", False)

        async def keystroke_handler(keystroke):
            """This function is called every time a key is pressed."""
            if keystroke.keycode != iterm2.Keycode.ESCAPE:
                return

            # There might not be a current session, so there might be an exception
            # while trying to get it.
            try:
                session = app.current_terminal_window.current_tab.current_session
            except:
                return

            # The status bar coro will only be called when the variable changes,
            # so the value must be different each time. This only matters if you
            # press esc while reset() is still sleeping.
            global counter
            counter += 1
            await session.async_set_variable("user.showEscIndicator", counter)

        async def coro(show_indicator, session_id, knobs):
            """This function gets called when showEscIndicator changes in any
            session."""
            if show_indicator:
                if session_id in tasks:
                    tasks[session_id].cancel()
                    del tasks[session_id]

                task = asyncio.create_task(reset(app.get_session_by_id(session_id)))
                tasks[session_id] = task
                return "[ESC]"
            else:
                return "     "

        # The user variable `showEscIndicator` is used as a communications channel
        # between the keyboard monitor and the status bar component coro. Since it
        # may not always be defined (e.g., when a new session is created) it must be
        # labeled as optional with the trailing ? to prevent an exception.
        defaults = { "show_indicator": "user.showEscIndicator?",
                     "session_id": "session.id" }

        # Register the status bar component.
        await component.async_register(connection, coro, defaults=defaults)

        # Monitor the keyboard
        async with iterm2.KeystrokeMonitor(connection) as mon:
            while True:
                keystroke = await mon.async_get()
                await keystroke_handler(keystroke)

    iterm2.run_forever(main)

