.. _gmtclock_example:

GMT Clock
=========

This script demonstrates a custom status bar component that shows the time in GMT, updating once a second.

.. code-block:: python

    import iterm2
    import datetime

    async def main(connection):
	component = iterm2.StatusBarComponent(
	    short_description="GMT Clock",
	    detailed_description="Shows the time in jolly old England",
	    knobs=[],
	    exemplar="[12:00 GMT]",
	    update_cadence=1,
	    identifier="com.iterm2.example.gmt-clock")

	# This function gets called once per second.
	@iterm2.StatusBarRPC
	async def coro(knobs):
	    return datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M:%S GMT")

	# Register the component.
	await component.async_register(connection, coro)

    iterm2.run_forever(main)
