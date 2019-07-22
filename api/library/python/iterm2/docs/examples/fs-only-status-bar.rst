.. _fsonlystatusbar_example:

Show Status Bar Only in Full Screen Windows
============================================

This script automatically shows or hides the status bar depending on the window's style. Full screen windows get a status bar, and regular windows do not. It demonstrates a few concepts:

  * Watching for window style changes.
  * Performing an action on all windows, including those not yet created.
  * Using asyncio to run multiple tasks concurrently.
  * Changing a profile setting in a session without updating the underlying profile.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def set_show_status_bar(w, show):
            """Show or hide the status bar for one window by updating the profiles
            of all sessions in that window."""
            change = iterm2.LocalWriteOnlyProfile()
            change.set_status_bar_enabled(show)
            tasks = []
            for tab in w.tabs:
                for session in tab.sessions:
                    tasks.append(session.async_set_profile_properties(change))
            await asyncio.gather(*tasks)

        async def update():
            """Update whether the status bar is shown for all sessions in all windows."""
            tasks = []
            for w in app.terminal_windows:
                style = await w.async_get_variable("style")
                if style == "non-native full screen" or style == "native full screen":
                    tasks.append(set_show_status_bar(w, True))
                else:
                    tasks.append(set_show_status_bar(w, False))
            if tasks:
                await asyncio.gather(*tasks)

        async def watch_for_style_changes():
            """A task that calls `update` when a window's style changes."""
            async with iterm2.VariableMonitor(connection, iterm2.VariableScopes.WINDOW, "style", "all") as mon:
                while True:
                    theme = await mon.async_get()
                    await update()

        async def watch_for_layout_changes():
            """A task that calls `update` when the layout changes (new window
            created, session moves from one window to another, etc.)"""
            async with iterm2.LayoutChangeMonitor(connection) as mon:
                while True:
                    await mon.async_get()
                    await update()

        # Set status bars for existing windows
        await update()

        # Monitor changes to styles in windows.
        asyncio.create_task(watch_for_style_changes())

        # Monitor for new windows or sessions moving from one window to another.
        asyncio.create_task(watch_for_layout_changes())

    iterm2.run_forever(main)

:Download:`Download<fs-only-status-bar.its>`
