:orphan:

.. _resizeall_example:

Resize Font in All Sessions in Window
=====================================

This script registers a function that resizes the font of all sessions in a window. To use it, place it in `~/Library/Application Support/iTerm2/Scripts/AutoLaunch`. Then restart iTerm2 or launch it manually. Then add keybindings with the action *Invoke Script Function…* and use a command of `change_font_size(session_id:id,delta:1)` for the keystroke that will make the font bigger and `change_font_size(session_id:id,delta:-1)` for the keystroke that will make the font smaller.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2
    import re

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        # This regex splits the font into its name and size. Fonts always end with
        # their size in points, preceded by a space.
        r = re.compile(r'^(.* )(\d*)$')

        async def change_font_size_session(session, delta):
            """Change the size of the font in a session by `delta` points."""
            # Get the session's profile because we need to know its font.
            profile = await session.async_get_profile()

            # Extract the name and point size of the font using a regex.
            font = profile.normal_font
            match = r.search(font)
            if not match:
                return
            groups = match.groups()
            name = groups[0]
            size = int(groups[1])

            # Prepare an update to the profile that increases the font size
            # by 6 points.
            replacement = name + str(size + delta)
            change = iterm2.LocalWriteOnlyProfile()
            change.set_normal_font(replacement)

            # Update the session's copy of its profile without updating the
            # underlying profile.
            await session.async_set_profile_properties(change)

        @iterm2.RPC
        async def change_font_size(session_id, delta):
            """Change the font size of all sessions in the window containing the
            session whose ID is `session_id` by `delta` points."""
            session = app.get_session_by_id(session_id)
            if not session:
                return
            tasks = []
            for tab in session.tab.window.tabs:
                for s in tab.sessions:
                    tasks.append(change_font_size_session(s, delta))
            await asyncio.gather(*tasks)
        await change_font_size.async_register(connection)

    iterm2.run_forever(main)


:Download:`Download<resizeall.its>`
