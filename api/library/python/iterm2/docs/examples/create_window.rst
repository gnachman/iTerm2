Create Window — Custom Escape Sequence
======================================

This demonstrates handling a custom escape sequence to perform an action. In
this case, the action is to create a new window. This script is meant to be a
starting point for developing your own custom escape sequence handler.

.. code-block:: python

    import iterm2

    async def main(connection):
        async with iterm2.CustomControlSequenceMonitor(
                connection, "shared-secret", r'^create-window$') as mon:
            while True:
                match = await mon.async_get()
                await iterm2.Window.async_create(connection)

    iterm2.run_forever(main)

To run the script, use:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The *shared-secret* string is used to prevent untrusted code from invoking your
function. For example, if you `cat` a text file, it could include escape
sequences, but they won't work unless they contain the proper secret string.
