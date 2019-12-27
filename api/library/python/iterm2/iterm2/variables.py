"""
Provides support for iTerm2 variables, which hold information associated
with various objects such as sessions, tabs, and windows.
"""

import asyncio
import enum
import json
import typing

import iterm2.connection
import iterm2.notifications


class VariableScopes(enum.Enum):
    """Describes the scope in which a variable can be evaluated."""
    SESSION = iterm2.api_pb2.VariableScope.Value("SESSION")  #: Session scope
    TAB = iterm2.api_pb2.VariableScope.Value("TAB")  #: Tab scope
    WINDOW = iterm2.api_pb2.VariableScope.Value("WINDOW")  #: Window scope
    APP = iterm2.api_pb2.VariableScope.Value("APP")  #: Whole-app scope


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
            connection: iterm2.connection.Connection,
            scope: VariableScopes,
            name: str,
            identifier: typing.Optional[str]):
        self.__connection = connection
        self.__scope = scope
        self.__name = name
        self.__identifier = identifier
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a variable changes."""
            await self.__queue.put(message)

        self.__token = await (
            iterm2.notifications.
            async_subscribe_to_variable_change_notification(
                self.__connection,
                callback,
                self.__scope.value,
                self.__name,
                self.__identifier))
        return self

    async def async_get(self) -> typing.Any:
        """Returns the new value of the variable."""
        result = await self.__queue.get()
        json_new_value = result.json_new_value
        return json.loads(json_new_value)

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass
