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

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def on_custom_esc(connection, notification):
            print("Received a custom escape sequence")
            if notification.sender_identity == "shared-secret":
                if notification.payload == "create-window":
                    await iterm2.Window.async_create()

        await iterm2.notifications.async_subscribe_to_custom_escape_sequence_notification(connection, on_custom_esc)

        await connection.async_dispatch_until_future(asyncio.Future())

    iterm2.run(main)

Let's examine it line by line.

.. code-block:: python

    #!/usr/bin/env python3

This is standard boilerplate for a Python script. See :doc:`running` for
details on how scripts are run.

The next part of the template script are the imports:

.. code-block:: python

    import asyncio

The `iterm2` module is based on the Python :py:mod:`asyncio` framework. For
simple scripts, you don't need to know about it at all, but as you do more
complex things it will become more important. This script uses an
:py:class:`asyncio.Future` to get it to run indefinitely, which you'll see
later.

.. code-block:: python

    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

This is the same stuff you saw in the first example.

.. code-block:: python

        async def on_custom_esc(connection, notification):
            print("Received a custom escape sequence")

This is a callback that gets invoked when iTerm2 receives a custom escape
sequence.

A custom escape sequence is a special escape sequence that performs a
user-defined action. In contradistinction to a standard escape sequence, such
as those that position the cursor or change the current color, a custom escape
sequence is propritary to iTerm2. When one is received, iTerm2 sends a
notification to any script that has subscribed to custom escape sequence
notifications. The `iterm2` python module invokes the script's registered
callback, which in this case is `on_custom_esc`.

The first argument is a `connection`, which you have seen before.

The second argument is a `notification`, which contains details about the
notification. In the case of a custom escape sequence, it has a
`sender_identity` and a `payload`. The `sender_identity` is intended to be a
secret shared between your daemon and the program that produces a custom escape
sequence. This is a security measure to prevent untrusted programs from using a
daemon to control iTerm2 in ways you don't want.

The `payload` is an arbitrary string provided in the custom escape sequence.

.. note::
    The `notification` is a Python representation of a Google protobuf message.
    You can find the protobuf description in the `api.proto
    <https://raw.githubusercontent.com/gnachman/iTerm2/master/proto/api.proto>`_
    file.

    The :doc:`/notifications` documentation describes which protobuf message to
    expect in a notification callback.

To produce a custom escape sequence, you could run this at the command line:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The first argument, `shared-secret` is the identity and the second argument,
`create-window` is the payload.

Let's see what the callback does:

.. code-block:: python

            if notification.sender_identity == "shared-secret":
                if notification.payload == "create-window":
                    await iterm2.Window.async_create()

First, it checks that the sender identity is correct. Next, it selects the
action to perform based on the payload. This daemon only knows how to create
windows, but a more sophisticated daemon could handle many different payloads.

That's it for the callback. Let's see how we register for custom escape
sequence notifications:

.. code-block:: python

    await iterm2.notifications.async_subscribe_to_custom_escape_sequence_notification(connection, on_custom_esc)

That's all you have to do to request that `on_custom_esc` be called any time a
custom escape sequence is received in any session.

The last thing the script needs to do is to keep running indefinitely:

.. code-block:: python

    await connection.async_dispatch_until_future(asyncio.Future())

This tells the `connection` to handle incoming messages until the passed-in
future has its result set. The future will never have its result set, so the
script will run until iTerm2 terminates.

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
