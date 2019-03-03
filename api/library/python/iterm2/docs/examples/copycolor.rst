.. _copycolor_example:

Preserve Tab Color
==================

If you split a session using a different profile. you can end up with two panes that have different tab colors. This script copies the old tab color to the new split pane so they stay in sync.

This script demonstrates how to modify a session's profile without modifying the underlying profile (which might affect other sessions).

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
        async def async_color_in_tab(tab, exclude):
            """Return the tab color of any session that already existed."""
            colors = []
            for session in tab.sessions:
                if session == exclude:
                    continue
                profile = await session.async_get_profile()
                if not profile:
                    continue
                color = profile.tab_color
                if color:
                    return color
            return None


        app = await iterm2.async_get_app(connection)
        async with iterm2.NewSessionMonitor(connection) as mon:
            while True:
                # Wait for a new session to be created
                session_id = await mon.async_get()
                session = app.get_session_by_id(session_id)
                if not session:
                    continue
                window, tab = app.get_tab_and_window_for_session(session)
                if not tab:
                    continue
                color = await async_color_in_tab(tab, session)
                if not color:
                    continue

                # Another session had a color in this tab. Change the tab
                # color property of the new session. Use LocalWriteOnlyProfile
                # and session.async_set_profile_properties to avoid changing the
                # underlying profile.
                change = iterm2.LocalWriteOnlyProfile()
                change.set_tab_color(color)
                await session.async_set_profile_properties(change)

    iterm2.run_forever(main)

:Download:`Download<copycolor.its>`

