.. _setprofile_example:

Change Session's Profile
------------------------

This script changes the current session's profile to the profile named "Default". It demonstrates getting the list of profiles and changing a session's profile.

Note that if the session is divorced from its underlying profile (such as by making a change in the **Session > Edit Session** panel) then those changes will not be affected by this script. In order to override them, you should convert the partial profile `partial` into a full profile by calling `await partial.async_get_full_profile()` and passing that to `async_set_profile`.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
	app = await iterm2.async_get_app(connection)
	# Query for the list of profiles so we can search by name. This returns a
	# subset of the full profiles so it's fast.
	partialProfiles = await iterm2.PartialProfile.async_query(connection)
	# Iterate over each partial profile
	for partial in partialProfiles:
	    if partial.name == "Default":
		# This is the one we're looking for. Change the current session's
		# profile.
		full = await partial.async_get_full_profile()
		await app.current_terminal_window.current_tab.current_session.async_set_profile(full)
		return

    iterm2.run_until_complete(main)

:Download:`Download<setprofile.its>`

