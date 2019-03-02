.. _oneshot_example:

One-Shot Alert
==============

This script registers a function that shows an alert. It's useful as a trigger with the **Invoke Script Function** action. It will only fire once per process, so if one program causes the trigger to fire multiple times you will only get alerted once.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    pids = []

    async def main(connection):
	@iterm2.RPC
	async def oneshot_alert(
		title,
		subtitle,
		pid=iterm2.Reference("jobPid")):
	    global pids
	    if pid in pids:
		return
	    pids.append(pid)
	    alert = iterm2.Alert(title, subtitle)
	    await alert.async_run(connection)
	await oneshot_alert.async_register(connection)

    iterm2.run_forever(main)


:Download:`Download<oneshot.its>`
