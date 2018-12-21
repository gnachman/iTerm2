Daemons
=======

A daemon in the Unix tradition is a computer program that runs as a background
process, rather than being under the direct control of an interactive user.

An iTerm2 daemon would ordinarily be an AutoLaunch script that provides some
service, such as listening for notifications and reacting to them. Autolaunch
scripts should be placed in `~/Library/Application Support/iTerm2/Scripts/AutoLaunch`.

AutoLaunch scripts are launched at startup. When you create a new one it does
not get launched until iTerm2 is restarted, but you can always run it by
selecting it from the **Scripts** menu.

When you create a new script and choose to make it a "Long-Running Daemon" (as
opposed to a "Simple" script), iTerm2 will provide a sample program to help you
get started:


.. code-block:: python

    #!/usr/bin/env python3
    import iterm2

    async def main(connection):
        async def my_callback(match):
            await iterm2.Window.async_create(connection)

        my_sequence = iterm2.CustomControlSequence(
            connection=connection,
            callback=my_callback,
            shared_secret="shared-secret",
            regex=r'^create-window$')

        await my_sequence.async_register()

    iterm2.run_forever(main)

Skipping the boilerplate we've seen before, let's look at the meat of the `main`
function.

.. code-block:: python

        async def my_callback(match):
            await iterm2.Window.async_create(connection)

This is a callback that gets invoked when iTerm2 receives a custom control
sequence.

A custom escape sequence is a special control sequence that performs a
script-defined action. In contradistinction to a standard control sequence, such
as those that position the cursor or change the current color, a custom control
sequence is proprietary to iTerm2. When one is received, iTerm2 sends a
notification to any script that has subscribed to custom escape sequence
notifications. The `iterm2` python module invokes the script's registered
callback, which in this case is `my_callback`.

The callback takes a single argument, `match`, which is from Python's `re`
regular expression module. The control sequence's payload gets matched against
a regular expression you provide. If the search is successful, the resulting
`re.Match` gets passed to your callback.

To produce a custom escape sequence, you could run this at the command line:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The first argument, `shared-secret` is the identity and the second argument,
`create-window` is the payload.

The callback simply creates a new window, as a demonstration of what could
be done here.

.. code-block:: python

        async def my_callback(match):
            await iterm2.Window.async_create(connection)

That's it for the callback. Let's see how we register for custom escape
sequence notifications:

.. code-block:: python

        my_sequence = iterm2.CustomControlSequence(
            connection=connection,
            callback=my_callback,
            identity="shared-secret",
            regex=r'^create-window$')

        await my_sequence.async_register()

That's all you have to do to request that `my_callback` be called any time a
custom escape sequence is received in any session with the specified identity
and a payload matching the regular expression `^create-window$`.

If you wanted the payload to take more information, such as the number of
windows to create, you could use the regular expression matcher to capture
that value in a capture group and retrieve it from the matcher in the callback.

The control sequence remains registered even after `main` returns.

Finally, we get to the last line of the script:

.. code-block:: python

    iterm2.run_forever(main)

This starts the script and keeps it running even after `main` returns so it can
continue to process custom control sequences until iTerm2 terminates. This is
what makes it a long-running daemon.

Continue to the next section, :doc:`rpcs`.

----

--------------
Other Sections
--------------

* :doc:`/index`
    * :doc:`index`
    * :doc:`example`
    * :doc:`running`
    * Daemons
    * :doc:`rpcs`
    * :doc:`hooks`

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
