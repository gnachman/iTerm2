Daemons
=======

A daemon in the Unix tradition is a computer program that runs as a background
process, rather than being under the direct control of an interactive user.

An iTerm2 daemon would ordinarily be an AutoLaunch script that provides some
ongoing service. For example, it might enable you to create a window when a
special string is printed. Such a script lies dormant until it is needed, so it
must run at all times.

AutoLaunch scripts are launched at startup.  Autolaunch scripts should be placed in
`~/Library/Application Support/iTerm2/Scripts/AutoLaunch`. When you create a
new one it does not get launched until iTerm2 is restarted, but you can always
run it by selecting it from the **Scripts** menu.

When you create a new script and choose to make it a "Long-Running Daemon" (as
opposed to a "Simple" script), iTerm2 will provide a sample program to help you
get started:


.. code-block:: python

    #!/usr/bin/env python3
    import iterm2

    async def main(connection):
        async with iterm2.CustomControlSequenceMonitor(
                connection, "shared-secret", r'^create-window$') as mon:
            while True:
                match = await mon.async_get()
                await iterm2.Window.async_create(connection)

    iterm2.run_forever(main)

:Download:`Download<tutorial_daemon.its>`

Skipping the boilerplate we've seen before, let's look at the meat of the `main`
function.

.. code-block:: python

        async with iterm2.CustomControlSequenceMonitor(
                connection, "shared-secret", r'^create-window$') as mon:

This is how you use an asyncio context manager.

`iterm2.CustomControlSequenceMonitor` is a special kind of class that defines
a context manager. That means it can perform an asyncio operation when it is
created and when the context ends.

This particular context manager registers a hook for custom control sequences.
Terminal emulators work by processing out-of-band messages called control
sequences to perform actions such as moving the cursor, clearing the screen, or
changing the current text color. Custom control sequences allow you to define your
own actions to perform when a control sequence you define is received.

When you use a context manager this way the flow of control enters the body of
the context manager (beginning with `while True`).

The `async_get` call blocks until a control sequence matching the requested
identity and payload are received. It returns a `re.Match` object, which is
the result of searching the control sequence's payload with the regular
expression that the `CustomControlSequenceMonitor` was initialized with.

To produce a custom escape sequence, you could run this at the command line:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"

The first argument, `shared-secret` is the identity and the second argument,
`create-window` is the payload. Here's the body of the context manager:

.. code-block:: python

        while True:
            match = await mon.async_get()
            await iterm2.Window.async_create(connection)

After receiving a matching control sequence, this example creates a new window.

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

If you want to run multiple context managers concurrently, such as to register
two different custom control sequences, you need to create tasks that run in the
background. Otherwise, the flow of control will get stuck in the first one since
its body has a `while True` infinite loop. Here's how you do that:

.. code-block:: python

    async def wrapper():
        async with iterm2.CustomControlSequenceMonitor(
                connection, identity, regex) as mon:
            while True:
                DoSomething(await mon.async_get())

    asyncio.create_task(wrapper())
    # Define more wrappers and create more tasks

As you browse the documentation you will find many different context managers
that allow you to perform actions when something hapens. For example:

* :class:`iterm2.FocusMonitor`
* :class:`iterm2.KeystrokeFilter`
* :class:`iterm2.KeystrokeMonitor`
* :class:`iterm2.LayoutChangeMonitor`
* :class:`iterm2.NewSessionMonitor`
* :class:`iterm2.PromptMonitor`
* :class:`iterm2.ScreenStreamer`
* :class:`iterm2.SessionTerminationMonitor`
* :class:`iterm2.Transaction`
* :class:`iterm2.VariableMonitor`

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
