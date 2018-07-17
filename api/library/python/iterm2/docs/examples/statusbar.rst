Status Bar Component
====================

This example demonstrates registering a Python function to provide the content of a custom status bar component. It features a "knob" that allows configuration: in this case, whether to display the size of the session or a happy face instead.

After starting this script, navigate to **Preferences > Profiles > Session**. Turn on **Status Bar Enabled** and select **Configure Status Bar**. Drag the **Status Bar Demo** component into the bottom section. Select it and then click **Configure Component**. You'll see a "Happy face?" setting that can be toggled to change the component's behavior. Other standard knobs, like color adjustments, are also present.

This script is a long-running daemon since the registered function gets called whenever the size of a session changes. As such, it should go in the AutoLaunch folder.

.. code-block:: python

    import iterm2
    import asyncio

    async def main(connection, argv):
        app=await iterm2.async_get_app(connection)

        # Define the configuration knobs:
        happy = "HAPPY_FACE"
        knobs = [iterm2.StatusBarComponent.Knob(
                     iterm2.StatusBarComponent.Knob.TYPE_CHECKBOX,
                     "Happy Face?",
                     "",
                     "false",
                     happy)]

        # Define the settings of the component
        component = iterm2.StatusBarComponent(
            "StatusBarDemo",
            "Status Bar Demo",
            "Tests script-provided status bar components",
            knobs,
            "row x cols",
            None)

        # This function gets called whenever any of the paths named in defaults (below) changes
        # or its configuration changes.
        async def coro(rows, cols, knobs):
          if happy in knobs and knobs[happy]:
            return ":)"
          return "{}x{}".format(rows, cols)

        # Defaults specify paths to external variables (like session.rows) and binds them to
        # arguments to the registered function (coro). When any of those variables' values
        # change the function gets called.
        defaults = { "rows": "session.rows",
                     "cols": "session.columns" }

        # Register the component.
        await app.async_register_status_bar_component(component, coro, defaults=defaults)

        # Wait forever
        future = asyncio.Future()
        await connection.async_dispatch_until_future(future)

    if __name__ == "__main__":
	iterm2.Connection().run(main, sys.argv)
