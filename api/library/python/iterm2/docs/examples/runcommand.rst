:orphan:

.. _runcommand_example:

Run a Command and Return its Output
===================================

This script runs a command and prints its output to stdout.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def wait_for_prompt(connection, my_session):
	"""Block until the running command terminates."""
	modes = [iterm2.PromptMonitor.Mode.COMMAND_END]
	async with iterm2.PromptMonitor(connection, my_session.session_id, modes) as prompt_monitor:
	    while True:
		type, value = await prompt_monitor.async_get()
		if type == iterm2.PromptMonitor.Mode.COMMAND_END:
		    return

    async def string_in_lines(my_session, start_y, end_y):
	"""Returns a string with the content in a range of lines."""
	contents = await my_session.async_get_contents(start_y, end_y - start_y)
	result = ""
	for line in contents:
	    result += line.string
	    if line.hard_eol:
		result += "\n"
	return result

    async def run_command(connection, my_session, command):
	"""Run a command and return its output. Requires shell integration."""
	# Atomically get the last prompt, send a command, and begin watching for the end of the command.
	async with iterm2.Transaction(connection):
	    prompt = await iterm2.async_get_last_prompt(connection, my_session.session_id)
	    await my_session.async_send_text(command + "\r")
	    task = asyncio.create_task(wait_for_prompt(connection, my_session))

	# Wait for the command to end.
	await task

	# Re-fetch the prompt for the command we sent to get the current output range.
	async with iterm2.Transaction(connection):
	    prompt = await iterm2.async_get_prompt_by_id(connection, my_session.session_id, prompt.unique_id)
	    range = prompt.output_range
	    start_y = range.start.y
	    end_y = range.end.y

	    # Fetch the content in that range and return it
	    content = await string_in_lines(my_session, start_y, end_y)
	return content

    async def main(connection):
	"""Demonstrate how to use run_command"""
	app = await iterm2.async_get_app(connection)
	if app.current_terminal_window:
	    my_session = app.current_terminal_window.current_tab.current_session
	    print(await run_command(connection, my_session, "seq 150"))

    iterm2.run_until_complete(main)

:Download:`Download<runcommand.its>`
