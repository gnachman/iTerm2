"""Provides information about the shell prompt."""
import asyncio
import iterm2.connection
import iterm2.notifications

class PromptMonitor:
    """An asyncio context manager to watch for changes to the prompt.
    
    This requires shell integration or prompt-detecting triggers to be installed for prompt detection.
    
    :param connection: The :class:`iterm2.connection.Connection` to use.
    :param session_id: The string session ID to monitor.

    Example:

      .. code-block:: python

          async with iterm2.PromptMonitor(connection, my_session.session_id) as mon:
              while True:
                  await mon.async_get()
                  DoSomething()
    """
    def __init__(self, connection, session_id):
        self.connection = connection
        self.session_id = session_id
        self.__queue = asyncio.Queue(loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a new prompt is shown."""
            await self.__queue.put(message)

        self.__token = await iterm2.notifications.async_subscribe_to_prompt_notification(
                self.connection,
                callback,
                self.session_id)
        return self

    async def async_get(self):
        """Blocks until a new shell prompt is received."""
        await self.__queue.get()

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)
