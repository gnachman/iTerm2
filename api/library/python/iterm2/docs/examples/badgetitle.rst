Badge in Tab Title
==================

The script puts the badge name in the tab title. This demonstrates a very simple custom title.

First run the script. Then choose "Badge + Name" in **Prefs > Profiles > General > Title**.

.. code-block:: python

    #!/usr/bin/env python3

    import iterm2

    async def main(connection):
        async def title(badge, auto_name):
            if badge and auto_name:
                return auto_name + u" \u2014 " + badge
            elif auto_name:
                return auto_name
            elif badge:
                return badge
            else:
                return "Shell"

        defaults = { "badge": "session.badge?",
                     "auto_name": "session.autoName?" }
        await iterm2.Registration.async_register_session_title_provider(
                connection,
                "nameandbadge",
                title,
                display_name="name + badge",
                defaults=defaults)

    iterm2.run_forever(main)
