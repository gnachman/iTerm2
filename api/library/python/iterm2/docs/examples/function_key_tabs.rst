.. _function_key_tabs_example:

Function Key Tabs
=================

The script makes it possible to select a tab by pressing a function key. F1 chooses the first tab, F2 the second, etc.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        keycodes = [ iterm2.Keycode.F1,
                     iterm2.Keycode.F2,
                     iterm2.Keycode.F3,
                     iterm2.Keycode.F4,
                     iterm2.Keycode.F5,
                     iterm2.Keycode.F6,
                     iterm2.Keycode.F7,
                     iterm2.Keycode.F8,
                     iterm2.Keycode.F9,
                     iterm2.Keycode.F10,
                     iterm2.Keycode.F11,
                     iterm2.Keycode.F12 ]
        async def keystroke_handler(connection, keystroke):
            if keystroke.modifiers == [ iterm2.Modifier.FUNCTION ]:
                try:
                  fkey = keycodes.index(keystroke.keycode)
                  if fkey >= 0 and fkey < len(app.current_terminal_window.tabs):
                      await app.current_terminal_window.tabs[fkey].async_select()
                except:
                  pass


        pattern = iterm2.KeystrokePattern()
        pattern.forbidden_modifiers.extend([iterm2.Modifier.CONTROL,
                                            iterm2.Modifier.OPTION,
                                            iterm2.Modifier.COMMAND,
                                            iterm2.Modifier.SHIFT,
                                            iterm2.Modifier.NUMPAD])
        pattern.required_modifiers.extend([iterm2.Modifier.FUNCTION])
        pattern.keycodes.extend(keycodes)

        async def monitor():
            async with iterm2.KeystrokeMonitor(connection) as mon:
                while True:
                    keystroke = await mon.async_get()
                    await keystroke_handler(connection, keystroke)
        # Run the monitor in the background
        asyncio.create_task(monitor())

        # Block regular handling of function keys
        filter = iterm2.KeystrokeFilter(connection, [pattern])
        async with filter as mon:
            await iterm2.async_wait_forever()

    iterm2.run_forever(main)


:Download:`Download<function_key_tabs.its>`
