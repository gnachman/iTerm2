:orphan:

.. _open_browser_tab_example:

Open a URL in a Browser Tab
===========================

This script creates a new tab configured as a web browser and loads a URL in it.

A profile becomes a browser profile by setting its ``Custom Command`` value to ``Browser``. The example passes that customization to :meth:`~iterm2.window.Window.async_create_tab` and then calls :meth:`~iterm2.session.Session.async_load_url` on the resulting session.

The first time a domain is loaded, iTerm2 prompts the user to approve it. Once approved, the domain is remembered globally and will not prompt again.

.. code-block:: python

    #!/usr/bin/env python3
    import sys
    import iterm2


    async def main(connection):
        url = sys.argv[1] if len(sys.argv) > 1 else "https://example.com/"

        app = await iterm2.async_get_app(connection)
        window = app.current_terminal_window
        if window is None:
            window = await iterm2.Window.async_create(connection)

        customizations = iterm2.LocalWriteOnlyProfile()
        customizations.set_use_custom_command("Browser")

        tab = await window.async_create_tab(profile_customizations=customizations)
        if tab is None or tab.current_session is None:
            print("Failed to create browser tab.", file=sys.stderr)
            return

        await tab.current_session.async_load_url(url)


    iterm2.run_until_complete(main)

Run it from the command line:

.. code-block:: bash

    python3 open_browser_tab.py https://iterm2.com/

:Download:`Download<open_browser_tab.its>`
