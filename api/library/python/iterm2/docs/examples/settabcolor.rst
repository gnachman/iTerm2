.. _settabcolor_example:

Set Tab Color
-------------

This script sets the tab color for the current session to a hard-coded value. It also turns on the use of tab color for that session. It does not modify the underlying profile, so only the current session is affected.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
        app=await iterm2.async_get_app(connection)
        session=app.current_terminal_window.current_tab.current_session
        change = iterm2.LocalWriteOnlyProfile()
        color = iterm2.Color(255, 128, 128)
        change.set_tab_color(color)
        change.set_use_tab_color(True)
        await session.async_set_profile_properties(change)

    iterm2.run_until_complete(main)

:Download:`Download<settabcolor.its>`
