.. _theme_example:

Change Color Presets On Theme Change
====================================

This script changes the color presets of all profiles when the theme changes. It demonstrates `VariableMonitor`, which lets you know when a variable changes. It also demonstrates how to use color presets.

.. code-block:: python

    #!/usr/bin/env python3

    import asyncio
    import iterm2

    async def main(connection):
        async with iterm2.VariableMonitor(connection, iterm2.VariableScopes.APP, "effectiveTheme", None) as mon:
            while True:
                # Block until theme changes
                theme = await mon.async_get()

                # Themes have space-delimited attributes, one of which will be light or dark.
                parts = theme.split(" ")
                if "dark" in parts:
                    preset = await iterm2.ColorPreset.async_get(connection, "Dark Background")
                else:
                    preset = await iterm2.ColorPreset.async_get(connection, "Light Background")

                # Update the list of all profiles and iterate over them.
                profiles=await iterm2.PartialProfile.async_get(connection)
                for partial in profiles:
                    # Fetch the full profile and then set the color preset in it.
                    profile = await partial.async_get_full_profile()
                    await profile.async_set_color_preset(preset)

    iterm2.run_forever(main)

:Download:`Download<theme.its>`
