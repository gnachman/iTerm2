:orphan:

.. _venv_example:

Show Python Virtual Environment
===============================

This custom status bar component shows the current Python virtual environment. In order to expose the necessary info to iTerm2 you need to add this to your `.bashrc`:

.. code-block:: bash

    iterm2_print_user_vars()
    {
        iterm2_set_user_var python_venv $VIRTUAL_ENV
    }


You can then add it to your status bar in **Prefs > Profiles > Session > Configure Status Bar**.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
        python_venv_component = iterm2.StatusBarComponent(
            short_description="Python virtual environment",
            detailed_description="Show the currently active Python virtual environment",
            knobs=[
                iterm2.CheckboxKnob("Show even if unset?", False, "force"),
                iterm2.CheckboxKnob("Shorten to trailing directory?", True, "shorten"),
            ],
            exemplar="🐍\N{THIN SPACE}~/pyvenvs/default",
            update_cadence=None,
            identifier="com.livinglogic.walter.iterm.status.python-venv")

        @iterm2.StatusBarRPC
        async def python_venv_callback(
            knobs,
            python_venv=iterm2.Reference("user.python_venv?")
        ):
            if python_venv:
                if "shorten" in knobs and knobs["shorten"]:
                    python_venv = python_venv.rsplit("/")[-1]
                return f"🐍\N{THIN SPACE}{python_venv}"
            elif "force" in knobs and knobs["force"]:
                return f"🐍\N{THIN SPACE}\N{TWO-EM DASH}"
            else:
                return ""

        await python_venv_component.async_register(connection, python_venv_callback)


    iterm2.run_forever(main)


:Download:`Download<venv.its>`

