Badge in Tab Title
==================

The script puts the badge name in the tab title. This demonstrates a very simple custom title.

First run the script. Then choose "Badge + Name" in **Prefs > Profiles > General > Title**.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
	async def title(badge, auto_name):
	    if badge:
		return auto_name + u" \u2014 " + badge
	    else:
		return auto_name

	defaults = { "badge": "session.badge?",
		     "auto_name": "session.autoname?" }
	await iterm2.registration.async_register_session_title_provider(
		connection,
		"nameandbadge",
		title,
		display_name="name + badge",
		defaults=defaults)

    iterm2.run_forever(main)
