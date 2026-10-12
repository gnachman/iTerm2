"""Enables defining a custom control sequence."""

from __future__ import annotations

import re
from asyncio import Queue
from typing import TYPE_CHECKING

from . import api_pb2
from .notifications import (
    SubscriptionException,
    async_subscribe_to_custom_escape_sequence_notification,
    async_unsubscribe,
)

if TYPE_CHECKING:
    import types

    from typing_extensions import Self

    from .connection import Connection
    from .notifications import NotificationToken


class CustomControlSequenceMonitor:
    """Registers a handler for a custom control sequence.

    :param connection: The connection to iTerm2.
    :param identity: A string that must be provided as the sender identity in
        the control sequence. This is a shared secret, to make it harder to
        invoke control sequences without permission.
    :param regex: A regular expression. It will be used to search the payload.
        If it matches, the resulting `re.Match` is returned from `async_get()`.
    :param session_id: The session ID to monitor, or `None` to mean monitor all
        sessions (including those not yet created).

    .. seealso:: Example ":ref:`create_window_example`"

    Example:

      .. code-block:: python

          async with iterm2.CustomControlSequenceMonitor(
                  connection,
                  "shared-secret",
                  r'^create-window$') as mon:
              while True:
                  match = await mon.async_get()
                  await iterm2.Window.async_create(connection)
    """

    def __init__(
        self,
        connection: Connection,
        identity: str,
        regex: str,
        session_id: str | None = None,
    ) -> None:
        self.__connection = connection
        self.__regex = regex
        self.__identity = identity
        self.__session_id = session_id
        self.__token: NotificationToken | None = None
        self.__queue: Queue[re.Match[str]] = Queue()

    async def __aenter__(self) -> Self:
        async def internal_callback(
            _connection: Connection,
            notification: api_pb2.CustomEscapeSequenceNotification,
        ):
            if notification.sender_identity != self.__identity:
                return
            match = re.search(self.__regex, notification.payload)
            if not match:
                return
            await self.__queue.put(match)

        self.__token = await async_subscribe_to_custom_escape_sequence_notification(
            self.__connection, internal_callback, self.__session_id
        )
        return self

    async def async_get(self) -> re.Match[str]:
        """
        Blocks until a matching control sequence is returned.

        :returns: A `re.Match` produced by searching the control sequence's
            payload with the regular expression this object was initialized
            with.
        """
        return await self.__queue.get()

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: types.TracebackType | None,
    ) -> None:
        try:
            await async_unsubscribe(self.__connection, self.__token)  # type: ignore[arg-type]
        except SubscriptionException:
            pass
