Tmux Integration
================

This example demonstrates creating windows using the tmux integration.

First, attach to at least one tmux session using `tmux -CC`. This script will create a window with two tabs in the first tmux session.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2
    import sys

    async def main(connection, argv):
        app = await iterm2.async_get_app(connection)
        # Get an array of tmux integration connections
        tmux_conns = await iterm2.async_get_tmux_connections(connection)
        # Pick the first one
        tmux_conn = tmux_conns[0]
        # Create a new window
        window = await tmux_conn.async_create_window()
        # Add a second tab to that window
        tab2 = await window.async_create_tmux_tab(tmux_conn)

    if __name__ == "__main__":
        iterm2.Connection().run(main, sys.argv)
