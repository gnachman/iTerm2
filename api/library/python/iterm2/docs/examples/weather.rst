.. _weather_example:

Web-Based Status Bar
====================

This script periodically fetches a URL that gives your local weather conditions, and displays its content in the status bar.

It demonstrates a custom status bar component that has an icon. It also demonstrates fetching a URL using `aiohttp`.

Because this script uses `aiohttp` you must install that package. To manually install this script, you'd need to select "Full Environment" when creating the script. Then you must add `aiohttp` as a dependency.

Alternately, download the `its` file below which will take care of installing `aiohttp` for you.

Status bar components should usually be placed in the `AutoLaunch` folder so they'll always be running. You'll need to manually launch it the first time, or else restart iTerm2 to have it launched automatically.

.. code-block:: python

    #!/usr/bin/env python3.7

    import iterm2
    import asyncio
    import aiohttp

    # How often to request the URL
    UPDATE_INTERVAL = 60 * 10

    # The URL to request
    URL = 'https://wttr.in/?format=%l:+%c+%t+%h'

    # The name of the iTerm2 variable to store the result
    VARIABLE = "weather"

    # Icons are base64-encoded PNGs. The first one is 32x34 and is used for Retina
    # displays. The second is 16x32 and is used for non-Retina displays.
    ICON2X = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAiCAYAAAA+stv/AAAABGdBTUEAALGPC/xhBQAAAWJJREFUWMPtVzsOgkAQRRIas4UdsTI0FhzDG1BwChrOYW1nTaPewsIL2JDY2HgBKisdk0cyEl2XWcniZ5KXEJiZ99hdZgbP+5udnQBndgG+T8CAMHyjgCFyGpMvCVuCeuE7BnSmkGtpKiIkHPFmTREBISUUhJJQASXupfBpkl+QMzRdhYiJWOFeQjiwZX+GA3w9xNbkUdtzcAvYEaaEOSPYE3JCjDdUuM7xrPabI3YnIedWk58JGcHX+PrwOTMRVpYw8lmLuBkTkUjJA7bnmSA+Y2cikAhI2Z77gnifnYlUIqBAcG6xhTlyFJLgEsGxhYAYOUrTrsa7W4VgZSFAIUel4bmr6by2dyHgEc9dTee1vYsteMTT30Po/DN0Xoicl2Lnzej2CS0II4t2PEIOJSGvJ5m1xUCyeTJZGZM3J5m2I1mkGe9eChCNUZrxrvUqTN74ZzSxLOk/+Gf0MQKMulqv7Qpwm6+awd/XXAAAAABJRU5ErkJggg=="

    ICON = "iVBORw0KGgoAAAANSUhEUgAAABAAAAARCAYAAADUryzEAAAABGdBTUEAALGPC/xhBQAAAK9JREFUOMtjYKAxqIRiskE9FBMFvIDYEYgZoXxJIDaHYkmoGEjOCYg9sRnABMQWQKwDxLuA+BoQz4Ti61AxkEZ+qFqsgAuIbwNxGZoiJqjYbaganKANiOfikZ8LVYMTnAFiYzzyxlA1GFH1GYnmwWMAD5pacBSzQiVYSXABsh7qhgHFsaAExHZ40gFIThGX5iAg1gBiZmiKk4T62RgpJYLkYoBYd3BmJmyAFVtUIQMAZuAlWgiKRrsAAAAASUVORK5CYII="

    async def updater(app):
        """A background tasks that reloads URL every UPDATE_INTERVAL seconds and
        sets the app-scope 'user.{VARIABLE}' variable."""
        global value
        while True:
            async with aiohttp.ClientSession() as session:
                async with session.get(URL) as response:
                    text = await response.text()
                    if text:
                        await app.async_set_variable("user." + VARIABLE, text.rstrip())
                        await asyncio.sleep(UPDATE_INTERVAL)
                    else:
                        asyncio.sleep(5)

    async def main(connection):
        app = await iterm2.async_get_app(connection)
        # Start fetching the URL
        asyncio.create_task(updater(app))

        icon = iterm2.StatusBarComponent.Icon(1, ICON)
        icon2x = iterm2.StatusBarComponent.Icon(2, ICON2X)

        # Register the status bar component.
        component = iterm2.StatusBarComponent(
            short_description="Weather",
            detailed_description="Shows your local weather",
            knobs=[],
            exemplar="😎",
            update_cadence=None,
            identifier="com.iterm2.example.weather",
            icons=[icon,icon2x])

        @iterm2.StatusBarRPC
        async def coro(knobs, value=iterm2.Reference("iterm2.user." + VARIABLE + "?")):
            """This function returns the value to show in a status bar."""
            if value:
                return value
            return "Loading…"

        # Register the component.
        await component.async_register(connection, coro)

    iterm2.run_forever(main)

:Download:`Download<weather.its>`
