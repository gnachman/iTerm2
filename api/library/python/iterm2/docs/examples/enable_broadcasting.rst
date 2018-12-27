Enable Broadcasting Input
=========================

This example demonstrates how to manipulate which sessions broadcast input. It turns on input broadcasting for the first session in each tab of the first window.

Input broadcasting happens among the sessions belonging to a particular window.

There may be multiple "broadcast domains". Each broadcast domain has a collection of sessions belonging to a window. There may not be more than one broadcast domain per window.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        domain = iterm2.broadcast.BroadcastDomain()
        for tab in app.terminal_windows[0].tabs:
            domain.add_session(tab.sessions[0])
        await iterm2.async_set_broadcast_domains([domain])


    iterm2.run_until_complete(main)
