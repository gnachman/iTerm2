:orphan:

.. _sumselection_example:

Sum Selection
=============

This script registers a custom context menu item that sums the integers in selected text and then injects the sum at the cursor location.

To use it, select one or more numbers. Right click and choose "Sum Selection". The sum of the numbers will appear at the cursor location.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2
    import re

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        @iterm2.ContextMenuProviderRPC
        async def execute(session_id=iterm2.Reference("id"), text=iterm2.Reference("selection")):
            parts = re.split('(\s+)', text)
            sum = 0
            for part in parts:
                try:
                    sum += int(part)
                except:
                    pass
            session = app.get_session_by_id(session_id)
            await session.async_inject(str.encode(str(sum)))

        await execute.async_register(connection, "Sum Selection", "com.iterm2.example.sum-selection")

    iterm2.run_forever(main)

:Download:`Download<sumselection.its>`

