.. _launch_and_run_example:

Launch iTerm2 and Run Command
=============================

This script demonstrates two concepts:

1. Launching iTerm2 using PyObjC and running the script only
   after it is launched.
2. Creating a window that runs a command.

Launching the app is useful when the script is run from the
command line rather than from within iTerm2. To run this
script from the command line you'll need to install its
dependencies first:

.. code-block:: bash

    brew install python3
    pip3 install iterm2
    pip3 install pyobjc

Here's the code:

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2
    import AppKit

    # Launch the app
    AppKit.NSWorkspace.sharedWorkspace().launchApplication_("iTerm2")

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        # Foreground the app
        await app.async_activate()

        # This will run 'vi' from bash. If you use a different shell, you'll need
        # to change it here. Running it through the shell sets up your $PATH so you
        # don't need to specify a full path to the command.
        await iterm2.Window.async_create(connection, command="/bin/bash -l -c vi")

    # Passing True for the second parameter means keep trying to
    # connect until the app launches.
    iterm2.run_until_complete(main, True)

:Download:`Download<launch_and_run.py>`
