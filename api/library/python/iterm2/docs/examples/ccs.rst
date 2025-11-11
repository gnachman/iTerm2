:orphan:

.. _ccs_example:

Custom Escape Sequence
======================

This demonstrates handling a custom escape sequence to perform an action so that
you can identify wihch session used the custom control sequence.

.. code-block:: python

    import asyncio
    import iterm2

    tasks = {}

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        tmtask = asyncio.create_task(monitor_termination(connection))
        async with iterm2.EachSessionOnceMonitor(app) as mon:
            while True:
                session_id = await mon.async_get()
                print(session_id)
                session = app.get_session_by_id(session_id)
                task = asyncio.create_task(monitor_ccs(connection, session, session_id))
                tasks[session_id] = task

    async def monitor_ccs(connection, session, session_id):
        try:
            print(f'Monitor {session_id}')
            async with iterm2.CustomControlSequenceMonitor(
                    connection, "shared-secret", r'^split$', session_id) as mon:
                while True:
                    match = await mon.async_get()
                    print(f'Will split {session_id}')
                    await session.async_split_pane()
        except Exception as e:
            print(f'Exception in {session_id}: {e}')

    async def monitor_termination(connection):
        global tasks
        try:
            async with iterm2.SessionTerminationMonitor(connection) as mon:
                while True:
                    print("Waiting for termination")
                    session_id = await mon.async_get()
                    print("Session {} closed".format(session_id))
                    task = tasks[session_id]
                    del tasks[session_id]
                    print("Cancel task")
                    task.cancel()
                    print("await task")
                    await task
                    print("End of loop")
        except Exception as e:
            print(f'Exception in {session_id}: {e}')

    iterm2.run_forever(main)


:Download:`Download<ccs.its>`

To split the current session while this script is running, invoke this command:

.. code-block:: bash

    printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "split"

The *shared-secret* string is used to prevent untrusted code from invoking your
function. For example, if you `cat` a text file, it could include escape
sequences, but they won't work unless they contain the proper secret string.

