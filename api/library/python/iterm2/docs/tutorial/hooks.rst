Hooks
=====

iTerm2 provides a mechanism called *hooks* that allows your Python code to modify the app's default behavior.

The following hooks are defined:

* Session title provider
* Status bar provider

Begin by reading about RPCs as described in :doc:`rpcs`. Hooks are similar, but each uses a different decorator.

Session Title Provider
----------------------

A session title provider is an RPC that accepts information about the current
session as input and returns a string to be shown in the tab bar or window
title.

Here's a minimal example that takes the "auto name" of the session and converts
it to upper case. The auto name is the "normal" session name. It defaults to
the profile name and can be changed by the control sequence that sets the
title, by a trigger that sets the title, or by the user editing the session
name in the *Edit Session* window.
to be the upper-case version of the session name.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
        @iterm2.TitleProviderRPC
        async def upper_case_title(auto_name=iterm2.Reference("autoName?")):
            if not auto_name:
                return ""
            return auto_name.upper()

        await upper_case_title.async_register(
            connection,
            display_name="Upper-case Title",
            unique_identifier="com.iterm2.example.upper-case-title")

    iterm2.run_forever(main)

:Download:`Download<tutorial_title.its>`

The `display_name` is shown to the user in Profile Preferences.

The `unique_identifier` is a string that identifies this title provider. The
algorithm and function signature and function name may change over time, but as
long as the unique identifier remains the user will not need to update their
preferences.

When this script is running and the user navigates to **Prefs > Profiles >
General** and opens the **Title** menu, your title provider will appear there
with this name.

When does the RPC get run? It is always run once when it gets attached to a
session. Thereafter, it is run when any variable with an `iterm2.Reference` as
a default value of an argument of your RPC changes.

If some variable might not be defined, you should put a `?` after its name to signify that a
value of `None` is allowed. Variables are detailed in
`Scripting Fundamentals <https://www.iterm2.com/documentation-scripting-fundamentals.html>`_.

Force Reevaluation
------------------

If you want to change the title in response to some external action, such as a timer, network request, or user action, you must cause a user-defined variable to change. Here is a full working example that sets the session title to its age in seconds:

.. code-block:: python

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        tasks = {}

        async def redraw_title_provider_periodically(session_id):
           try:
                age = 0
                session = app.get_session_by_id(session_id)
                while True:
                    await asyncio.sleep(1)
                    # When the session ends, this will raise an exception.
                    await session.async_set_variable(
                        "user.session_age_in_seconds", age)
                    age += 1
           except Exception as e:
               traceback.print_exc()
           finally:
                del tasks[session_id]

        @iterm2.TitleProviderRPC
        async def age_in_seconds_title(
                session_id=iterm2.Reference("id"),
                age=iterm2.Reference("user.session_age_in_seconds?")):
            if session_id not in tasks:
                wake_coro = redraw_title_provider_periodically(session_id)
                tasks[session_id] = asyncio.create_task(wake_coro)
            return str(age)

        await age_in_seconds_title.async_register(
            connection,
            display_name="Age in Seconds",
            unique_identifier="com.iterm2.example.age-in-seconds")

    iterm2.run_forever(main)

:Download:`Download<tutorial_age.its>`

Installation
------------

Since a title provider is a long-running daemon, you'll want to put it in
`~/Library/Application Support/iTerm2/Scripts/AutoLaunch` folder.

Next, you need to configure your session's profile to use the hook. Once it's been registered properly it will appear as an option in **Preferences > Profiles > General > Title**. Select it there:

.. image:: choose_custom_session_title.png

Custom Status Bar Component
---------------------------

A custom status bar component is another kind of hook. Like a title provider, it
lives in a long-running daemon. It registers an RPC that provides the text to
display in the status bar component. It may also register a second RPC to handle
clicks in the status bar component.

Here's a simple status bar component that shows whether mouse reporting is on:

.. code-block:: python

    import asyncio
    import iterm2

    async def main(connection):
        component = iterm2.StatusBarComponent(
            short_description="Mouse Mode",
            detailed_description="Indicates if mouse reporting is enabled",
            knobs=[],
            exemplar="[mouse on]",
            update_cadence=None,
            identifier="com.iterm2.example.mouse-mode")

        # This function gets called when the mouseReportingMode variable
        # changes.
        @iterm2.StatusBarRPC
        async def coro(
                knobs,
                reporting=iterm2.Reference("mouseReportingMode")):
            if reporting < 0:
                return " "
            else:
                return "🐭"

        # Register the component.
        await component.async_register(connection, coro)

    iterm2.run_forever(main)

When this script is running, a new status bar component becomes available in
*Prefs > Profiles > Session > Configure Status Bar*.

Like a title provider, the registered function will be called when its
references change. The string it returns will go in the status bar.

Status bar components can also be invoked periodically, by passing a number of
seconds to the `update_cadence` argument of `StatusBarComponent`'s initializer.

Status bar components can also define configuration settings, called knobs.

For more information, see :class:`iterm2.StatusBarComponent`. There are also a
number of status bar components in the :doc:`/examples/index`.

Continue to the next section, :doc:`troubleshooting`.

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
    * :doc:`troubleshooting`

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
