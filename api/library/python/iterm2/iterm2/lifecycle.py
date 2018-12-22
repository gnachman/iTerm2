"""Provides hooks for session life-cycle events."""
import asyncio
import iterm2

class SessionTerminationMonitor:
    """
    Watches for session termination.

    A session is said to terminate when its command (typically `login`) has exited. If the user closes a window, tab, or split pane they can still undo closing it for some amount of time. Session termination will be delayed until it is no longer undoable.

    :param connection: The :class:`iterm2.Connection` to use.

    Example:

      .. code-block:: python

          async with iterm2.SessionTerminationMonitor(connection) as mon:
              while True:
                  session_id = await mon.async_get()
                  print("Session {} closed".format(session_id))
    """
    def __init__(self, connection):
        self.__connection = connection
        self.__queue = asyncio.Queue(loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a session terminates."""
            await self.__queue.put(message.session_id)

        self.__token = await iterm2.notifications.async_subscribe_to_terminate_session_notification(
                self.__connection,
                callback)
        return self

    async def async_get(self):
        """
        Returns the session_id of a just-terminated session.
        """
        session_id = await self.__queue.get()
        return session_id

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(
                self.__connection,
                self.__token)
