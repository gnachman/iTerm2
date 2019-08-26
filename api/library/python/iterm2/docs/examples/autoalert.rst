.. _autoalert_example:

Alert on Long-Running Jobs
==========================

This script shows a notification when a job in any session runs for over thirty seconds.

It demonstrates creating a task for every session, monitoring for changes of the currently running command, posting notifications, and some basic asyncio usage.

This script requires that shell integration be installed in order to detect prompts and running commands.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    async def main(connection):
        app = await iterm2.async_get_app(connection)

        async def sleep_then_alert(connection, session):
            """Show a user notification in `session` if this task is allowed to run
            for 30 seconds."""
            await asyncio.sleep(30)
            code = "\u001b]9;Alert\u001b\\"
            await session.async_inject(str.encode(code))


        async def monitor(session_id):
            """Wait for commands to start or stop in this session.

            Start and cancel tasks to wait for long-running tasks."""
            session = app.get_session_by_id(session_id)
            if not session:
                return
            alert_task = None
            modes = [iterm2.PromptMonitor.Mode.PROMPT,
                     iterm2.PromptMonitor.Mode.COMMAND_START,
                     iterm2.PromptMonitor.Mode.COMMAND_END]
            async with iterm2.PromptMonitor(
                    connection, session_id, modes=modes) as mon:
                while True:
                    # This blocks until the status of the session changes. That
                    # happens when a new prompt appears, a command begins running,
                    # or a command finishes.
                    mode, info = await mon.async_get()
                    if alert_task:
                        # Cancel an existing task.
                        alert_task.cancel()
                    if mode == iterm2.PromptMonitor.Mode.COMMAND_START:
                        # A command has started running. Create a task that will
                        # alert if it runs for too long.
                        alert_task = asyncio.create_task(
                                sleep_then_alert(connection, session))

        # Create a task running `monitor` for each session, including those created
        # in the future.
        await iterm2.EachSessionOnceMonitor.async_foreach_session_create_task(
                app, monitor)

    # This instructs the script to run the "main" coroutine and to keep running
    # even after it returns.
    iterm2.run_forever(main)

:Download:`Download<autoalert.its>`

