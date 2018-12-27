"""Provides interfaces relating to keyboard focus."""
import asyncio
import enum
import iterm2.connection
import iterm2.notifications
import typing

class FocusUpdateApplicationActive:
    """Describes a change in whether the application is active."""
    def __init__(self, active):
        self.__application_active = active

    @property
    def application_active(self) -> bool:
        """:returns: `True` if the application is active or `False` if not."""
        return self.__application_active

class FocusUpdateWindowChanged:
    """Describes a change in which window is focused.

    This class defines three static constants:

    `TERMINAL_WINDOW_BECAME_KEY`: A terminal window received keyboard focus.
    `TERMINAL_WINDOW_IS_CURRENT`: A terminal window is current but some non-terminal window (such as Preferences) has keyboard focus.
    `TERMINAL_WINDOW_RESIGNED_KEY`: A terminal window no longer has keyboard focus."""

    TERMINAL_WINDOW_BECAME_KEY = 0
    TERMINAL_WINDOW_IS_CURRENT = 1
    TERMINAL_WINDOW_RESIGNED_KEY = 2
    TERMINAL_WINDOW_STRINGS = [ "WindowBecameKey", "WindowIsCurrent", "WindowResignedKey" ]

    def __init__(self, window_id: str, event: str):
        self.__window_id = window_id
        self.__event = event

    def __repr__(self):
        return "Window {}: {}".format(
            self.window_id,
            FocusUpdateWindowChanged.TERMINAL_WINDOW_STRINGS[self.event])

    @property
    def window_id(self) -> str:
        """:returns: the window ID of the window that changed."""
        return self.__window_id

    @property
    def event(self) -> 'FocusUpdateWindowChanged':
        """Describes how the window's focus changed.

        :returns: One of `FocusUpdateWindowChanged.TERMINAL_WINDOW_BECAME_KEY`, `FocusUpdateWindowChanged.TERMINAL_WINDOW_IS_CURRENT`, or `FocusUpdateWindowChanged.TERMINAL_WINDOW_RESIGNED_KEY`.
        """
        return self.__event

class FocusUpdateSelectedTabChanged:
    """Describes a change in the selected tab."""
    def __init__(self, tab_id: str):
        self.__tab_id = tab_id

    def __repr__(self):
        return "Tab selected: {}".format(self.tab_id)

    @property
    def tab_id(self) -> str:
        """
        :returns: A tab ID, which is a string.
        """
        return self.__tab_id

class FocusUpdateActiveSessionChanged:
    """Describes a change to the active session within a tab."""
    def __init__(self, session_id: str):
        self.__session_id = session_id

    def __repr__(self):
        return "Session activated: {}".format(self.session_id)

    @property
    def session_id(self) -> str:
        """Returns the active session ID within its tab.

        :returns: A session ID, which is a string.
        """
        return self.__session_id

class FocusUpdate:
    """Describes a change to keyboard focus.

    Up to one of `application_active`, `window_changed`, `selected_tab_changed`, or `active_session_changed` will not be `None`."""
    def __init__(
            self,
            application_active: FocusUpdateApplicationActive=None,
            window_changed: FocusUpdateWindowChanged=None,
            selected_tab_changed: FocusUpdateSelectedTabChanged=None,
            active_session_changed: FocusUpdateActiveSessionChanged=None):
        self.__application_active = application_active
        self.__window_changed = window_changed
        self.__selected_tab_changed = selected_tab_changed
        self.__active_session_changed = active_session_changed

    def __repr__(self):
        if self.__application_active:
            return str(self.__application_active)
        if self.__window_changed:
            return str(self.__window_changed)
        if self.__selected_tab_changed:
            return str(self.__selected_tab_changed)
        if self.__active_session_changed:
            return str(self.__active_session_changed)
        return "No Event"

    @property
    def application_active(self) -> typing.Union[None, FocusUpdateApplicationActive]:
        """:returns: `None` if no change to whether the app is active, otherwise :class:`FocusUpdateApplicationActive`"""
        return self.__application_active

    @property
    def window_changed(self) -> typing.Union[None, FocusUpdateWindowChanged]:
        """:returns: `None` if no change to the current window, otherwise :class:`FocusUpdateWindowChanged`."""
        return self.__window_changed

    @property
    def selected_tab_changed(self) -> typing.Union[None, FocusUpdateSelectedTabChanged]:
        """:returns: `None` if no change to selected tab, otherwise :class:`FocusUpdateSelectedTabChanged`."""
        return self.__selected_tab_changed

    @property
    def active_session_changed(self) -> typing.Union[None, FocusUpdateActiveSessionChanged]:
        """:returns: `None` if no change to active session, otherwise :class:`FocusUpdateActiveSessionChanged`."""
        return self.__active_session_changed

class FocusMonitor:
    """An asyncio context manager for monitoring keyboard focus changes.

    :param connection: A connection to iTerm2."""
    def __init__(self, connection: iterm2.connection.Connection):
        self.__connection = connection
        self.__queue = []

    async def __aenter__(self):
        async def async_callback(_connection, message):
            """Called when focus changes."""
            print("fasync_callback: set future's result")
            self.__queue.append(message)
            future = self.__future
            if future is None:
                print("async_callback: return becasue reentrant")
                # Ignore reentrant calls
                return

            self.__future = None
            if future is not None and not future.done():
                print("async_callback: set result")
                temp = self.__queue[0]
                del self.__queue[0]
                future.set_result(temp)
            else:
                print("async_callback: no future or future is done")

        self.__token = await iterm2.notifications.async_subscribe_to_focus_change_notification(
                self.__connection,
                async_callback)
        return self

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.notifications.async_unsubscribe(self.__connection, self.__token)

    async def async_get_next_update(self) -> FocusUpdate:
        """
        When focus changes, returns an update.

        :returns: A :class:`FocusUpdate` object.

        Example:

        .. code-block:: python

            async with iterm2.FocusMonitor(connection) as monitor:
                while True:
                    update = await monitor.async_get_next_update()
                    if update.selected_tab_changed:
                        print("The active tab is now {}".format(update.selected_tab_changed.tab_id))
        """
        if self.__queue:
            print("async_get_next_update: return early with 1st value from queue")
            temp = self.__queue[0]
            del self.__queue[0]
            return self.handle_proto(temp)

        future = asyncio.Future()
        self.__future = future
        await self.__future
        proto = future.result()
        self.__future = None
        return self.handle_proto(proto)

    def handle_proto(self, proto):
        which = proto.WhichOneof('event')
        if which == 'application_active':
            return FocusUpdate(application_active=FocusUpdateApplicationActive(proto.application_active))
        elif which == 'window':
            return FocusUpdate(window_changed=FocusUpdateWindowChanged(proto.window.window_id, proto.window.window_status))
        elif which == 'selected_tab':
            return FocusUpdate(selected_tab_changed=FocusUpdateSelectedTabChanged(proto.selected_tab))
        elif which == 'session':
            return FocusUpdate(active_session_changed=FocusUpdateActiveSessionChanged(proto.session))
        else:
            return FocusUpdate()

