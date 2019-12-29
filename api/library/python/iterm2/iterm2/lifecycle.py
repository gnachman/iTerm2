"""Provides hooks for session life-cycle events."""
import asyncio

import iterm2.connection
import iterm2.notifications


class EachSessionOnceMonitor:
    """
    This is a convenient way to do something to all sessions exactly once,
    including those created in the future.

    You can use it as a context manager to get the session_id of each session,
    or you can use the static method `async_foreach_session_create_task` to
    have a task created for each session.

    :param connection: The :class:`~iterm2.connection.Connection` to use.
    :param app: An instance of :class:`~iterm2.app.App`.
    """
    def __init__(self, app: 'iterm2.app.App'):
        self.__connection = app.connection
        self.__app = app
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())

    @staticmethod
    async def async_foreach_session_create_task(app, task):
        """
        Create a task for each session. Cancels the task when the session
        terminates.

        Includes sessions in existence now and those created in the future.

        :param app: An instance of :class:`~iterm2.app.App`.
        :param task: A coro taking a single argument of session ID.
        :returns: A future.

        Example:

          .. code-block:: python

            app = await iterm2.async_get_app(connection)
            # Print a message to stdout when there's a new prompt in any
            # session
            async def my_task(session_id):
                async with iterm2.PromptMonitor(connection, session_id) as mon:
                    await mon.async_get()
                    print("Prompt detected")

            await (iterm2.EachSessionOnceMonitor.
                async_foreach_session_create_task(app, my_task))
        """
        tasks = {}

        async def each_mon():
            async with EachSessionOnceMonitor(app) as mon:
                while True:
                    session_id = await mon.async_get()
                    tasks[session_id] = asyncio.create_task(task(session_id))

        async def termination_mon():
            async with SessionTerminationMonitor(app.connection) as mon:
                while True:
                    session_id = await mon.async_get()
                    if session_id in tasks:
                        task = tasks[session_id]
                        del tasks[session_id]
                        task.cancel()
        await asyncio.gather(each_mon(), termination_mon())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a new session is created."""
            await self.__queue.put(message)

        self.__token = (
            await iterm2.notifications.
            async_subscribe_to_new_session_notification(
                self.__connection,
                callback))

        for window in self.__app.terminal_windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    await self.__queue.put(session)

        return self

    async def async_get(self) -> str:
        """Returns the session ID."""
        result = await self.__queue.get()
        session_id = result.session_id
        return session_id

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass


class SessionTerminationMonitor:
    """
    Watches for session termination.

    A session is said to terminate when its command (typically `login`) has
    exited. If the user closes a window, tab, or split pane they can still undo
    closing it for some amount of time. Session termination will be delayed
    until it is no longer undoable.

    :param connection: The :class:`~iterm2.connection.Connection` to use.

    Example:

      .. code-block:: python

          async with iterm2.SessionTerminationMonitor(connection) as mon:
              while True:
                  session_id = await mon.async_get()
                  print("Session {} closed".format(session_id))
    """
    def __init__(self, connection: iterm2.connection.Connection):
        self.__connection = connection
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a session terminates."""
            await self.__queue.put(message.session_id)

        self.__token = (
            await iterm2.notifications.
            async_subscribe_to_terminate_session_notification(
                self.__connection,
                callback))
        return self

    async def async_get(self) -> str:
        """
        Returns the `session_id` of a just-terminated session.
        """
        session_id = await self.__queue.get()
        return session_id

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection,
                self.__token)
        except iterm2.notifications.SubscriptionException:
            pass


class LayoutChangeMonitor:
    """
    Watches for changes to the composition of sessions, tabs, and windows.

    :param connection: The :class:`~iterm2.connection.Connection` to use.
    """
    def __init__(self, connection: iterm2.Connection):
        self.__connection = connection
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when the layout changes."""
            await self.__queue.put(message)

        self.__token = (
            await iterm2.notifications.
            async_subscribe_to_layout_change_notification(
                self.__connection, callback))
        return self

    async def async_get(self):
        """
        Blocks until the layout changes.

        Will block until any of the following occurs:

        * A session moves from one tab to another (including moving into its
          own window).
        * The relative position of sessions within a tab changes.
        * A tab moves from one window to another.
        * The order of tabs within a window changes.
        * A session is buried or disintered.

        Use :class:`~iterm2.App` to examine the updated application state.

       Example:

       .. code-block:: python

           async with iterm2.LayoutChangeMonitor(connection) as mon:
               while True:
                   await mon.async_get()
                   print("layout changed")

        """
        await self.__queue.get()

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass


class NewSessionMonitor:
    """Watches for the creation of new sessions.

      :param connection: The :class:`~iterm2.connection.Connection` to use.

      .. seealso::
          * Example ":ref:`colorhost_example`"
          * Example ":ref:`random_color_example`"

      Example:

      .. code-block:: python

          async with iterm2.NewSessionMonitor(connection) as mon:
              while True:
                  session_id = await mon.async_get()
                  print("Session ID {} created".format(session_id))

        .. seealso::
            * Example ":ref:`autoalert`"
      """
    def __init__(self, connection: iterm2.Connection):
        self.__connection = connection
        self.__token = None
        self.__queue: asyncio.Queue = asyncio.Queue(
            loop=asyncio.get_event_loop())

    async def __aenter__(self):
        async def callback(_connection, message):
            """Called when a new session is created."""
            await self.__queue.put(message)

        self.__token = (
            await iterm2.notifications.
            async_subscribe_to_new_session_notification(
                self.__connection,
                callback))
        return self

    async def async_get(self) -> str:
        """Returns the new session ID."""
        result = await self.__queue.get()
        session_id = result.session_id
        return session_id

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass
