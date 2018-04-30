.. iTerm2 Python API Tutorial

iTerm2 Python API Tutorial
==========================

.. toctree::
   :maxdepth: 2
   :caption: Contents:

The iTerm2 Python API is a replacement for the Applescript API that preceded
it. It offers a more powerful set of APIs that give the script writer a great
deal of control.

Scripts generally take one of two forms:

  * "Simple" scripts that perform a series of actions, such as creating windows,
    * and then terminate.
  * "Long-running daemons" that stay running indefintely while observing
    * notifications.

Creating a New Script
---------------------

iTerm2 provides a convenient user interface for creating a new script. Select
*Scripts > New Python Script*. You'll then be prompted to decide if you want a
"basic" script or one with a "full environment". Don't worry about the
difference yet. Pick basic, since the code in this tutorial does not depend on
any Python modules besides the built-in ones.

Next, you'll be asked if you want to write a simple script or a long-running
daemon. Select simple. Then give your script a name, and it will be opened in
your editor.

The script will be prepopulated with a working example, shown below.

Working Example
---------------

To begin, let's look at a basic script that creates a window.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2
    import sys

    async def main(connection, argv):
	a = await iterm2.app.get_app(connection)
	w = await a.get_key_window()
	if w is not None:
	    await w.create_tab()
	else:
	    print("No current window")

    if __name__ == "__main__":
	iterm2.connection.Connection().run(main, sys.argv)

There's a lot going on here. Let's take it part by part.

.. code-block:: python

    #!/usr/bin/env python3

This is standard Python boilerplate so that the script can be run from the command line.

.. code-block:: python

    import asyncio
    import iterm2
    import sys

The first import is `asyncio`. The iTerm2 Python API is based on asyncio. If
you're not familiar with it, you should take some time to
`learn about it <https://docs.python.org/3/library/asyncio.html>`_.

The next import is `iterm2`. That's a Python module (available on PyPI) that
provides a nice interface to communicate with iTerm2. The underlying
implementation uses Google protobuf and websockets, but that is (mostly)
abstracted away by this module.

Finally, `sys` is imported so that the script can parse command-line arguments.

.. code-block:: python

    async def main(connection, argv):

Your code goes inside `main`. The first argument is a `connection` that holds
the link to a running iTerm2 process. If `main` gets called, then the
connection is established. If the connection terminates (e.g., if you quit
iTerm2) then any attempt to use it will raise an exception and terminate your
script.

The second argument, `argv`, gives the command-line arguments passed to the
script. When you launch a script from iTerm2, it does not receive any
arguments. But you can also run this script manually and pass it command-line
arguments.

.. code-block:: python

	a = await iterm2.app.get_app(connection)

The purpose of this line is to get a reference to the :class:`iterm2.app.App` object, which is
useful for most things you'll want to do in a simple script. It is a singleton
that provides access to iTerm2's global state, such as its windows.

Note the use of `await`. Any function that's defined as `async`, which most
functions in the iTerm2 API are, must be called with `await`. It means it might
not return immediately. In this case, it makes an RPC call to iTerm2 to get its
state (such as the list of windows). The returned value is an
:class:`iterm2.app.App`.

.. code-block:: python

	w = await a.get_key_window()

The fetches the "key window" from the app. The key window is the window that
receives keyboard input. If iTerm2 is not active or has no windows, then no
window will be key and `get_key_window` returns None.

.. code-block:: python

	if w is not None:
	    await w.create_tab()

If there is a key window, add a tab to it. The new tab uses the default
profile.

.. code-block:: python

	else:
	    print("No current window")

This prints a diagnostic message. You can view these messages in the Script
Console. Select *Scripts > Script Console* in iTerm2 to view the output of
your scripts. If something's not working right, you can usually find the
problem in the Script Console. You can also use it to terminate a misbehaving
script.

.. code-block:: python

    if __name__ == "__main__":
	iterm2.connection.Connection().run(main, sys.argv)

The `if` statement is a bit of standard Python boilerplate; you can ignore it
as its condition will always be True.

The next line establishes a websocket connection to iTerm2 and then runs your
`main` function, passing it `sys.argv` which holds the command-line arguments.
