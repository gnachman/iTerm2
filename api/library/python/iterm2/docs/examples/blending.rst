.. _blending_example:

Modify Background Image Blending
--------------------------------

This script demonstrates registering an RPC to adjust the image blending level of the current session. You can bind it to a keystroke by adding a new key binding in **Prefs > Keys**, selecting the action **Invoke Script Function**, and giving it the invocation `blend_more(session_id: id)` or `blend_less(session_id: id)`.

.. code-block:: python

    #!/usr/bin/env python3.7

    import asyncio
    import iterm2

    async def main(connection):
	app = await iterm2.async_get_app(connection)
	async def get_profile_for_session(session_id):
	    session = app.get_session_by_id(session_id)
	    return await session.async_get_profile()

	@iterm2.RPC
	async def blend_more(session_id):
	    profile = await get_profile_for_session(session_id)
	    await profile.async_set_blend(min(1, profile.blend + 0.1))
	await blend_more.async_register(connection)

	@iterm2.RPC
	async def blend_less(session_id):
	    profile = await get_profile_for_session(session_id)
	    await profile.async_set_blend(max(0, profile.blend - 0.1))
	await blend_less.async_register(connection)

    iterm2.run_forever(main)

:Download:`Download<blending.its>`
