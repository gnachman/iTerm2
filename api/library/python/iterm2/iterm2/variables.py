import asyncio
import enum
import iterm2.notifications
import json

class VariableScopes(enum.Enum):
    """Takes the following values:

    `SESSION`, `TAB`, `WINDOW`, `APP`
    """
    SESSION = iterm2.api_pb2.VariableScope.Value("SESSION")
    TAB = iterm2.api_pb2.VariableScope.Value("TAB")
    WINDOW = iterm2.api_pb2.VariableScope.Value("WINDOW")
    APP = iterm2.api_pb2.VariableScope.Value("APP")

class VariableMonitor:
    """Watches for changes to a variable.

      VariableMonitor is a context manager that helps observe changes in iTerm2 Variables.

      :param connection: The :class:`iterm2.Connection` to use.
      :param scope: A :class:`iterm2.VariableScope`, describing the context for the name and identifier.
      :param name: The variable name, a string.
      :param identifier: A tab, window, or session identifier. Must correspond to the passed-in scope. If the scope is `APP` this should be None.
        """
    def __init__(self, connection, scope, name, identifier):
        self.__connection = connection
        self.__scope = scope
        self.__name = name
        self.__identifier = identifier
        self.__queue = asyncio.Queue(loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a variable changes."""
            await self.__queue.put(message)

        self.__token = await iterm2.notifications.async_subscribe_to_variable_change_notification(
                self.__connection,
                callback,
                self.__scope.value,
                self.__name,
                self.__identifier)
        return self

    async def async_get(self):
        """
        Returns the new value of the variable.
        """
        result = await self.__queue.get()
        jsonNewValue = result.json_new_value
        return json.loads(jsonNewValue)

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)

