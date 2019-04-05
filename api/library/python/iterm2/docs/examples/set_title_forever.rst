.. _set_title_example:

Launch iTerm2 and Set Session Title
===================================

This script demonstrates two concepts:

1. Launching iTerm2 using PyObjC and running the script only
   after it is launched.
2. Setting a session's name.

Further, it demonstrates how to change a profile setting so
the session title can't be later changed by a control
sequence.

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

        # Create a new tab or window
        myterm = app.current_terminal_window
        if not myterm:
            myterm = await iterm2.Window.async_create(connection)
        else:
            await myterm.async_create_tab()
        await myterm.async_activate()

        # Update the name and disable future updates by
        # control sequences.
        #
        # Changing the name this way is equivalent to
        # editing the Session Name field in
        # Session>Edit Session.
        session = myterm.current_tab.current_session
        update = iterm2.LocalWriteOnlyProfile()
        update.set_allow_title_setting(False)
        update.set_name("This is my customized session name")
        await session.async_set_profile_properties(update)

    # Passing True for the second parameter means keep trying to
    # connect until the app launches.
    iterm2.run_until_complete(main, True)


Note that if you download and install the package below it will
install the needed dependencies for running this script from
within iTerm2 but your system Python configuration will not
be modified. You still need to follow the steps above to
install Python 3, the iterm2 Python module, and PyObjC if
you plan to run this from the command line.

:Download:`Download<set_title_forever.its>`
