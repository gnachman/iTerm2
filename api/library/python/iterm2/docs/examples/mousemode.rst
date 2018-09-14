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
        app=await iterm2.async_get_app(connection)

        component = iterm2.StatusBarComponent(
            "MouseMode",
            "Mouse Mode",
            "Indicates if mouse reporting is enabled",
            [],
            "[mouse on]",
            None)

        # This function gets called whenever any of the paths named in defaults (below) changes
        # or its configuration changes.
        async def coro(reporting, knobs):
            if reporting < 0:
                return " "
            else:
                return "🐭"

        # Defaults specify paths to external variables (like session.rows) and binds them to
        # arguments to the registered function (coro). When any of those variables' values
        # change the function gets called.
        defaults = { "reporting": "session.mouseReportingMode" }

        # Register the component.
        await iterm2.Registration.async_register_status_bar_component(connection, component, coro, defaults=defaults)

        # Wait forever
        future = asyncio.Future()
        await connection.async_dispatch_until_future(future)

    iterm2.run(main)


