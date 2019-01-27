.. _mrutabs_example:

MRU Tabs
========

This script keeps tabs in most-recently used order, with the current tab always first.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def reorder_tabs():
          window = app.current_terminal_window
          if not window:
              return
          if window.current_tab != window.tabs[0]:
              tabs = list(window.tabs)
              i = tabs.index(window.current_tab)
              del tabs[i]
              tabs.insert(0, window.current_tab)
              await window.async_set_tabs(tabs)

        async with iterm2.FocusMonitor(connection) as monitor:
            while True:
                update = await monitor.async_get_next_update()
                if update.selected_tab_changed:
                    await reorder_tabs()

    iterm2.run_forever(main)

:Download:`Download<mrutabs.its>`
