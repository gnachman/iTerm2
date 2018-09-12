import asyncio
import iterm2.notifications
import json

class VariableMonitor:
    """Watches for changes to a variable."""
    def __init__(self, connection, scope, name, identifier):
        self.__connection = connection
        self.__scope = scope
        self.__name = name
        self.__identifier = identifier
        self.__future = None

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a variable changes."""
            future = self.__future
            if future is None:
                # Ignore reentrant calls
                return

            self.__future = None
            if future is not None and not future.done():
                future.set_result(message)

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
        future = asyncio.Future()
        self.__future = future
        await self.__connection.async_dispatch_until_future(self.__future)
        result = future.result()
        self.__future = None

        jsonNewValue = result.json_new_value

        return json.loads(jsonNewValue)

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)

