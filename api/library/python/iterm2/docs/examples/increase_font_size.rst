:orphan:

.. _increase_font_size_example:

Increase Font Size By 6
=======================

This script increases the font size of a session by six
points. It demonstrates changing a session's profile without
updating the underlying profile. It also demonstrates
parsing and modifying font settings, as well as registering
an RPC.

You can bind it to a keystroke by adding a new key binding
in **Prefs > Keys**, selecting the action **Invoke Script
Function**, and giving it the invocation
`increase_font_size(session_id: id)`.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2
    import re

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        # This regex splits the font into its name and size. Fonts always end with
        # their size in points, preceded by a space.
        r = re.compile(r'^([^ ]* )(\d*)(.*)$')

        @iterm2.RPC
        async def increase_font_size(session_id):
            session = app.get_session_by_id(session_id)
            if not session:
                return
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
            remainder = groups[2]

            # Prepare an update to the profile that increases the font size
            # by 6 points.
            replacement = name + str(size + 6) + remainder
            change = iterm2.LocalWriteOnlyProfile()
            change.set_normal_font(replacement)

            # Update the session's copy of its profile without updating the
            # underlying profile.
            await session.async_set_profile_properties(change)
        await increase_font_size.async_register(connection)

    iterm2.run_forever(main)

:Download:`Download<increase_font_size.its>`
