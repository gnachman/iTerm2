.. _sorttabs_example:

Sort Tabs
=========

This script sorts the tabs in all windows by the name of the current session.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2
    import time

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        for window in app.terminal_windows:
            tabs = window.tabs
            for tab in tabs:
                tab.tab_name = await tab.async_get_variable("currentSession.name")
            def tab_name(tab):
                return tab.tab_name
            sorted_tabs = sorted(tabs, key=tab_name)
            await window.async_set_tabs(sorted_tabs)

    iterm2.run_until_complete(main)

:Download:`Download<sorttabs.its>`

