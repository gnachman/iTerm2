Status Bar Component
====================

This example demonstrates registering a Python function to provide the content of a custom status bar component. It features a "knob" that allows configuration: in this case, whether to show a demonstration of variable-length values, or to show the size of the current session.

After starting this script, navigate to **Preferences > Profiles > Session**. Turn on **Status Bar Enabled** and select **Configure Status Bar**. Drag the **Status Bar Demo** component into the bottom section. Select it and then click **Configure Component**. You'll see a "Variable-Length Demo" setting that can be toggled to change the component's behavior. Other standard knobs, like color adjustments, are also present.

When the **Variable-Length Demo** knob is on, try making the window narrower and observer that the text changes as the amount of available space changes.

This script is a long-running daemon since the registered function gets called whenever the size of a session changes. As such, it should go in the AutoLaunch folder.

.. code-block:: python

    import iterm2

    async def main(connection):
        # Define the configuration knobs:
        vl = "variable_length_demo"
        knobs = [iterm2.CheckboxKnob("Variable-Length Demo", False, vl)]
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
          if vl in knobs and knobs[vl]:
            return ["This is an example of variable-length status bar components",
                    "This is a demo of variable-length status bar components",
                    "This demo status bar component has variable length",
                    "Demonstrate variable-length status bar component",
                    "Shows variable-length status bar component",
                    "Shows variable-length text in status bar",
                    "Variable-length text in status bar",
                    "Variable-length text demo",
                    "Var. length text demo",
                    "It's getting tight" ]
          return "{}x{}".format(rows, cols)

        # Defaults specify paths to external variables (like session.rows) and binds them to
        # arguments to the registered function (coro). When any of those variables' values
        # change the function gets called.
        defaults = { "rows": "session.rows",
                     "cols": "session.columns" }

        # Register the component.
        await component.async_register(connection, coro, defaults=defaults)

    iterm2.run_forever(main)

