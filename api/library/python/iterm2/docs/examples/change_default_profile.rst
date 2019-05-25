.. _change_default_profile_example:

Change Default Profile
======================

This script changes the default profile. It is useful because a profile sourced
from a Dynamic Profile JSON file cannot ordinarily be made the default profile.
Put this in the AutoLaunch folder. It will run after dynamic profiles are
loaded at startup.


.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2

    async def main(connection):
        all_profiles = await iterm2.PartialProfile.async_query(connection)
        for profile in all_profiles:
            if profile.name == "Your Profile Name Goes Here":
                await profile.async_make_default()
                return

    iterm2.run_until_complete(main)

:Download:`Download<change_default_profile.its>`
