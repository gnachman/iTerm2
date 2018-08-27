#!/usr/bin/env python3

import asyncio
import iterm2
# This script was created with the "basic" environment which does not support adding dependencies
# with pip.

async def main(connection):
    app = await iterm2.async_get_app(connection)

    # This is an example of a callback function. In this template, on_custom_esc is called when a
    # custom escape sequence is received. You can send a custom escape sequence with this command:
    #
    # printf "\033]1337;Custom=id=%s:%s\a" "shared-secret" "create-window"
    async def on_custom_esc(connection, notification):
        print("Received a custom escape sequence")
        if notification.sender_identity == "shared-secret":
            if notification.payload == "create-window":
                await app.async_create_window()

    # Your program should register for notifications it wants to receive here. This example
    # watches for custom escape sequences.
    await iterm2.notifications.async_subscribe_to_custom_escape_sequence_notification(connection, on_custom_esc)

    # Wait for messages indefinitely. This program will terminate when iTerm2 exits because
    # dispatch_until_future will raise an exception when its connection closes.
    await connection.async_dispatch_until_future(asyncio.Future())

iterm2.run(main)
