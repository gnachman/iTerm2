Hooks
=====

iTerm2 provides a mechanism called *hooks* that allows your Python code to modify the app's default behavior.

The following hooks are defined:

* Custom session title
* (More TBD)

To define a hook, you must register an RPC as described in :doc:`rpcs`. There are a few things to do in addition:

1. Pass a `role` argument to `async_register_rpc_handler` that describes the hook you wish to implement.
2. Pass a `defaults` argument to `async_register_rpc_handler` that describes the variables you depend on.
3. Pass a `display_name` argument to `async_register_rpc_handler` that gives the name to show in the UI.

To implement a custom session title hook, use `role=RPC_ROLE_SESSION_TITLE`.

The `defaults` argument is a dictionary mapping an argument name to a variable.
The argument names in `defaults` correspond to argument names in the function
you register to handle the RPC. 

In the case of the custom session title hook, all arguments to your function
must have corresponding default values.

The values in the `defaults` dictionary refer to variables. When the value of
any named variable changes, the function may be re-evaluated. If some variable
might not be defined, you should put a `?` after its name to signify that a
null value is allowed. The function will be called with `None` for such
undefined variables. Variables are detailed in
`Badges <https://www.iterm2.com/documentation-badges.html>`_.

Here's an example:

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        async def custom_title(pwd, username, hostname):
            return "😀 {}@{}:{} 😀".format(pwd, username, hostname)

        defaults = { "pwd": "session.path?",
                     "username": "session.username?",
                     "hostname": "session.hostname?" }
        await iterm2.Registration.async_register_rpc_handler(connection,
                                                             "custom_title",
                                                             custom_title,
                                                             role=iterm2.RPC_ROLE_SESSION_TITLE,
                                                             defaults=defaults,
                                                             display_name="My Custom Title")
	await connection.async_dispatch_until_future(asyncio.Future())

    iterm2.run_forever(main)

As this script is a long-running daemon, you'll want to put it in the
`AutoLaunch` folder. If a hook is not registered then it acts as though it
returned an empty value. Tab labels will show a default value in place of the
empty string.

Next, you need to configure your session's profile to use the hook. Once it's been registered properly it will appear as an option in **Preferences > Profiles > General > Title**. Select it there:

.. image:: choose_custom_session_title.png

If anything goes wrong, remember to check the Script Console. Pick your script
on the left to view its output. Some errors are also logged to the *iTerm2 App*
history in the script console.

----

--------------
Other Sections
--------------

* :doc:`/index`
    * :doc:`index`
    * :doc:`example`
    * :doc:`running`
    * :doc:`daemons`
    * :doc:`rpcs`
    * Hooks

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
