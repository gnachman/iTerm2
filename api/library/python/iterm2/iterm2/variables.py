"""
Provides support for iTerm2 variables, which hold information associated
with various objects such as sessions, tabs, and windows.
"""

from __future__ import annotations

import enum
import json
from asyncio import Queue
from typing import TYPE_CHECKING, Any

from . import api_pb2
from .notifications import (
    SubscriptionException,
    async_subscribe_to_variable_change_notification,
    async_unsubscribe,
)

if TYPE_CHECKING:
    from types import TracebackType
    from typing import Self

    from .connection import Connection
    from .notifications import NotificationToken


class VariableScopes(enum.Enum):
    """Describes the scope in which a variable can be evaluated."""

    SESSION = api_pb2.VariableScope.Value("SESSION")  #: Session scope
    TAB = api_pb2.VariableScope.Value("TAB")  #: Tab scope
    WINDOW = api_pb2.VariableScope.Value("WINDOW")  #: Window scope
    APP = api_pb2.VariableScope.Value("APP")  #: Whole-app scope


class VariableMonitor:
    """
     Watches for changes to a variable.

     `VariableMonitor` is a context manager that helps observe changes in iTerm2
     Variables.

    :param connection: The connection to iTerm2.
    :param scope: The scope in which the variable should be evaluated.
    :param name: The variable name.
    :param identifier: A tab, window, or session identifier. Must correspond to
        the passed-in scope. If the scope is `APP` this should be None. If the
        scope is `SESSION` or `WINDOW` the identifier may be "all" or "active".

     .. seealso::
         * Example ":ref:`colorhost_example`"
         * Example ":ref:`theme_example`"

     Example:

       .. code-block:: python

           async with iterm2.VariableMonitor(
                   connection,
                   iterm2.VariableScopes.SESSION,
                   "jobName",
                   my_session.session_id) as mon:
               while True:
                   new_value = await mon.async_get()
                   DoSomething(new_value)
    """

    def __init__(
        self,
        connection: Connection,
        scope: VariableScopes,
        name: str,
        identifier: str | None,
    ) -> None:
        self.__connection = connection
        self.__scope = scope
        self.__name = name
        self.__identifier = identifier
        self.__token: NotificationToken | None = None
        self.__queue: Queue[api_pb2.VariableChangedNotification] = Queue()

    async def __aenter__(self) -> Self:
        async def callback(
            _connection: Connection, message: api_pb2.VariableChangedNotification
        ):
            """Called when a variable changes."""
            await self.__queue.put(message)

        self.__token = await async_subscribe_to_variable_change_notification(
            self.__connection,
            callback,
            self.__scope.value,
            self.__name,
            self.__identifier,
        )
        return self

    async def async_get(self) -> Any:
        """Returns the new value of the variable."""
        result = await self.__queue.get()
        json_new_value = result.json_new_value
        return json.loads(json_new_value)

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None:
        if self.__token is None:
            return
        try:
            await async_unsubscribe(self.__connection, self.__token)
        except SubscriptionException:
            pass
