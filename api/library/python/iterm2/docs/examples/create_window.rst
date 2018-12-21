Create Window — Custom Escape Sequence
======================================

This demonstrates handling a custom escape sequence to perform an action. In
this case, the action is to create a new window. This script is meant to be a
starting point for developing your own custom escape sequence handler.

.. code-block:: python

    import iterm2

    async def main(connection):
        async def my_callback(match):
            await iterm2.Window.async_create(connection)

        my_sequence = iterm2.CustomControlSequence(
            connection=connection,
            callback=my_callback,
            identity="shared-secret",
            regex=r'^create-window$')

        await my_sequence.async_register()

    iterm2.run_forever(main)

To run the script, use:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The *shared-secret* string is used to prevent untrusted code from invoking your
function. For example, if you `cat` a text file, it could include escape
sequences, but they won't work unless they contain the proper secret string.
