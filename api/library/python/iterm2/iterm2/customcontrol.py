"""Enables defining a custom control sequence."""
import iterm2.notifications
import re

class CustomControlSequence:
    def __init__(self, connection, callback, identity, regex, session_id=None):
        """Registers a handler for a custom control sequence.

        :param connection: The :class:`iterm2.Connection` to use.
        :param callback: A coroutine taking an `re.Match` as its only argument.
        :param identity: A string that must be provided as the sender identity (a shared secret, to make it harder to invoke control sequences without permission) in the control sequence.
        :param regex: A regular expression. It will be used to search the payload. If it matches, the resulting `re.Match` is passed to the `callback`.
        :param session_id: The session ID to monitor, or `None` to mean monitor all sessions (including those not yet created).

        Example:

          .. code-block:: python

              async def my_callback(match):
                  await iterm2.Window.async_create(connection)

              my_sequence = iterm2.CustomControlSequence(
                  connection=connection,
                  callback=my_callback,
                  identity="jaeger",
                  regex=r'^new_window$')

              await my_sequence.async_register()
        """
        self.__connection = connection
        self.__regex = regex
        self.__callback = callback
        self.__identity = identity
        self.__session_id = session_id
        self.__registered = False

    async def async_register(self):
        assert not self.__registered

        async def internal_callback(_connection, notification):
            if notification.sender_identity != self.__identity:
                return
            match = re.search(self.__regex, notification.payload)
            if not match:
                return
            await self.__callback(match)

        self.__token = await iterm2.notifications.async_subscribe_to_custom_escape_sequence_notification(
                self.__connection,
                internal_callback,
                self.__session_id)
        self.__registered = True

    async def async_unregister(self):
        assert self.__registered
        await iterm2.notifications.async_unsubscribe(
                self.__connection,
                self.__token)
        self.__registered = False
