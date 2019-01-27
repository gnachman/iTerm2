.. _mousemode_example:

Status Bar Component: Mouse Mode
================================

Like :doc:`statusbar`, this demonstrates a custom status bar component. The
difference is that this one displays the value of a variable: the mouse
reporting status.

After starting this script, navigate to **Preferences > Profiles > Session**.
Turn on **Status Bar Enabled** and select **Configure Status Bar**. Drag the
**Mouse Mode** component into the bottom section.

This script is a long-running daemon since the registered function gets called
whenever the size of a session changes. As such, it should go in the AutoLaunch
folder.

.. code-block:: python

    import asyncio
    import iterm2

    async def main(connection):
        component = iterm2.StatusBarComponent(
            short_description="Mouse Mode",
            detailed_description="Indicates if mouse reporting is enabled",
            knobs=[],
            exemplar="[mouse on]",
            update_cadence=None,
            identifier="com.iterm2.example.mouse-mode")

        # This function gets called whenever any of the paths named in defaults (below) changes
        # or its configuration changes. This will be called when mouseReportingMode changes.
        @iterm2.StatusBarRPC
        async def coro(
                knobs,
                reporting=iterm2.Reference("mouseReportingMode")):
            if reporting < 0:
                return " "
            else:
                return "🐭"

        # Register the component.
        await component.async_register(connection, coro)

    iterm2.run_forever(main)

:Download:`Download<mousemode.its>`
