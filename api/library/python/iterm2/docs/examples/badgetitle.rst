Badge or Window Name in Tab Title
=================================

The script puts the badge name in the tab title. This demonstrates a very simple custom title.

First run the script. Then choose "Badge + Name" in **Prefs > Profiles > General > Title**.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
        @iterm2.TitleProviderRPC
        async def badge_title(
            badge=iterm2.Reference("session.badge?"),
            auto_name=iterm2.Reference("session.autoName?")):
            if badge and auto_name:
                return auto_name + u" \u2014 " + badge
            elif auto_name:
                return auto_name
            elif badge:
                return badge
            else:
                return "Shell"
        await badge_title.async_register(connection, "Name + Badge", "com.iterm2.example.name-and-badge")

    iterm2.run_forever(main)

Another similar example demonstrates showing the window title in the tab.
Terminal apps may choose to set the window title without setting the tab title,
but some users prefer to see the window title in both places.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        @iterm2.TitleProviderRPC
        async def window_title_in_tab(
            window_name=iterm2.Reference("session.terminalWindowName?"),
            auto_name=iterm2.Reference("session.autoName?")):
            if window_name:
                return window_name
            elif auto_name:
                return auto_name
            else:
                return "Shell"

        await window_title_in_tab.async_register(connection, "Window Name", "com.iterm2.example.window-name")

    iterm2.run_forever(main)
