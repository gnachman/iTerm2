.. _tile_example:

Tile tmux Window Panes
======================

This example demonstrates sending arbitrary commands to the tmux server while in tmux integration.

First, attach to at least one tmux session using `tmux -CC`. Create a few tabs. Then run this script. It will tile the panes evenly.

.. code-block:: python

    import iterm2

    async def main(connection):
        tmux_conns = await iterm2.async_get_tmux_connections(connection)
        for tmux in tmux_conns:
            await tmux.async_send_command("select-layout tile")

    iterm2.run_until_complete(main)

:Download:`Download<tile.its>`
