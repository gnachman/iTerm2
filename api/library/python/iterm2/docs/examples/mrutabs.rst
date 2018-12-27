MRU Tabs
========

This script keeps tabs in most-recently used order, with the current tab always first.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def focus_callback(connection, notification):
          window = app.current_terminal_window
          if not window:
              return
          if window.current_tab != window.tabs[0]:
              tabs = list(window.tabs)
              i = tabs.index(window.current_tab)
              del tabs[i]
              tabs.insert(0, window.current_tab)
              await window.async_set_tabs(tabs)

        await iterm2.notifications.async_subscribe_to_focus_change_notification(connection, focus_callback)

    iterm2.run_forever(main)
