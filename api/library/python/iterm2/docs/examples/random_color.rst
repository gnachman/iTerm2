Random Color Preset
===================

The script demonstrates running some code when a new session is created. It picks a random color preset and changes the session's colors (without changing the underlying profile).

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2
    import random

    async def SetPresetInSession(connection, session, preset_name):
        preset = await iterm2.ColorPreset.async_get(connection, preset_name)
        if not preset:
            return
        profile = await session.async_get_profile()
        if not profile:
            return
        await profile.async_set_color_preset(preset)

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        color_preset_names = await iterm2.ColorPreset.async_get_list(connection)
        async with iterm2.NewSessionMonitor(connection) as mon:
            while True:
                session_id = await mon.async_get()
                session = app.get_session_by_id(session_id)
                if session:
                    await SetPresetInSession(connection, session, random.choice(color_preset_names))

    iterm2.run_forever(main)

