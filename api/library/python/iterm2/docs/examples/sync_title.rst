:orphan:

.. _sync_title_example:

Sync Pane Title to Tab
======================

This script automatically updates the tab title when a pane's title changes via a control sequence.

The following command changes a pane's "icon title":

.. code-block:: bash

    printf "\e]1;Hello world\a"

Each pane in a tab may have a different icon title. By default, a tab shows the icon title of the current pane.

This script copies the last-updated pane's icon title to the tab title so that the control sequence above has the effect of changing the tab title as well as the icon title.

Note that `printf "\\e]0;Hello world\\a"` changes both the icon title and the window title. This script will pick up on changes from that control sequence as well.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def watch_title(session_id):
            session = app.get_session_by_id(session_id)
            # When the session's "icon name" changes, update the tab title.
            # The icon name is set with OSC 0 and OSC 1.
            # e.g., ESC 0 ; title BEL
            async with iterm2.VariableMonitor(
                    connection,
                    iterm2.VariableScopes.SESSION,
                    "terminalIconName",
                    session_id) as mon:
                while True:
                    new_value = await mon.async_get()
                    # Note: it's unsafe to pass input from the session to async_set_title
                    # because it's an interpolated string. Instead, set a user variable
                    # (which can't do any computation) and then make the tab title
                    # show its contents.
                    await session.tab.async_set_variable("user.title", new_value)
                    await session.tab.async_set_title("\\(user.title)")

        # Make every session monitor its title.
        async with iterm2.EachSessionOnceMonitor(app) as mon:
            while True:
                session_id = await mon.async_get()
                coro = watch_title(session_id)
                asyncio.create_task(coro)

    iterm2.run_until_complete(main)

:Download:`Download<sync_title.its>`
