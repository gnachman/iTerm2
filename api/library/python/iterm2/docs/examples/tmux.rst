.. _tmux_example:

Tmux Integration
================

This example demonstrates creating windows using the tmux integration.

First, attach to at least one tmux session using `tmux -CC`. This script will create a window with two tabs in the first tmux session.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
        # Get an array of tmux integration connections
        tmux_conns = await iterm2.async_get_tmux_connections(connection)
        # Pick the first one
        tmux_conn = tmux_conns[0]
        # Create a new window
        window = await tmux_conn.async_create_window()
        # Add a second tab to that window
        tab2 = await window.async_create_tmux_tab(tmux_conn)

    iterm2.run_until_complete(main)

:Download:`Download<tmux.its>`
