:orphan:

.. _findps_example:

Find Pane with Process
----------------------

This script asks the user to input a process ID and then reveals the pane that contains it, if any.

It depends on `psutil`. If you create this manually, create a full environment script and specify `psutil` as a dependency.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2
    import psutil

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        alert = iterm2.TextInputAlert(
            "Search for process",
            "Enter a process ID to reveal the pane containing it.",
            "Enter the process ID to search for", "")
        query = await alert.async_run(connection)
        try:
          query = int(query)
        except:
          return

        desired = []
        try:
          while query > 1:
            desired.append(query)
            parent = psutil.Process(query).ppid()
            query = parent
        except:
          pass

        for window in app.windows:
          for tab in window.tabs:
            for session in tab.sessions:
              pid = await session.async_get_variable("pid")
              if pid in desired:
                await session.async_activate()
                return

    iterm2.run_until_complete(main)

:Download:`Download<findps.its>`
