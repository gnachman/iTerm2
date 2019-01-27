.. _current_preset_example:

Get Selected Color Preset
=========================

This script prints to stdout the name of the color preset the current
sesssion is using, or `None` if none of them matches.

To see the output you can either run `pip3 install iterm2` and then execute
this script from the command line or run it from the **Scripts** menu and view
the output in the **Script Console**.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    def ColorsUnequal(profile_color, preset_color):
        return (round(profile_color.red) != round(preset_color.red) or
                round(profile_color.green) != round(preset_color.green) or
                round(profile_color.blue) != round(preset_color.blue) or
                round(profile_color.alpha) != round(preset_color.alpha) or
                profile_color.color_space != preset_color.color_space)

    def ProfileUsesPreset(profile, preset):
        for preset_color in preset.values:
            key = preset_color.key
            profile_color = profile.get_color_with_key(key)
            if ColorsUnequal(profile_color, preset_color):
                return False
        return True

    async def PresetForProfile(connection, profile):
        presets=await iterm2.ColorPreset.async_get_list(connection)
        for preset_name in presets:
            preset=await iterm2.ColorPreset.async_get(connection, preset_name)
            if ProfileUsesPreset(profile, preset):
              return preset_name
        return None


    async def main(connection):
        app = await iterm2.async_get_app(connection)
        session=app.current_terminal_window.current_tab.current_session
        profile=await session.async_get_profile()
        print(await PresetForProfile(connection, profile))

    iterm2.run_until_complete(main)

:Download:`Download<current_preset.its>`
