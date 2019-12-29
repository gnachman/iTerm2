"""Provides interfaces relating to keyboard focus."""
import asyncio
import enum
import typing

import iterm2.api_pb2
import iterm2.connection
import iterm2.notifications


# pylint: disable=too-few-public-methods
class FocusUpdateApplicationActive:
    """Describes a change in whether the application is active."""
    def __init__(self, active):
        self.__application_active = active

    @property
    def application_active(self) -> bool:
        """:returns: `True` if the application is active or `False` if not."""
        return self.__application_active


class FocusUpdateWindowChanged:
    """Describes a change in which window is focused."""

    class Reason(enum.Enum):
        """Gives the reason for the change"""
        # pylint: disable=line-too-long
        TERMINAL_WINDOW_BECAME_KEY = 0  #: A terminal window received keyboard focus.
        TERMINAL_WINDOW_IS_CURRENT = 1  #: A terminal window is current but some non-terminal window (such as Preferences) has keyboard focus.
        TERMINAL_WINDOW_RESIGNED_KEY = 2  #: A terminal window no longer has keyboard focus.
        # pylint: enable=line-too-long

    def __init__(self, window_id: str, event: Reason):
        self.__window_id = window_id
        self.__event = event

    def __repr__(self):
        return "Window {}: {}".format(
            self.window_id,
            FocusUpdateWindowChanged.Reason(self.event).name)

    @property
    def window_id(self) -> str:
        """:returns: the window ID of the window that changed."""
        return self.__window_id

    @property
    def event(self) -> 'Reason':
        """Describes how the window's focus changed.

        :returns: The reason for the update.
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

    Up to one of `application_active`, `window_changed`,
    `selected_tab_changed`, or `active_session_changed` will not be `None`."""
    def __init__(
            self,
            application_active: FocusUpdateApplicationActive = None,
            window_changed: FocusUpdateWindowChanged = None,
            selected_tab_changed: FocusUpdateSelectedTabChanged = None,
            active_session_changed: FocusUpdateActiveSessionChanged = None):
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
    def application_active(self) -> typing.Union[
            None, FocusUpdateApplicationActive]:
        """
        :returns: `None` if no change to whether the app is active,
            otherwise :class:`FocusUpdateApplicationActive`"""
        return self.__application_active

    @property
    def window_changed(self) -> typing.Union[None, FocusUpdateWindowChanged]:
        """
        :returns: `None` if no change to the current window, otherwise
            :class:`FocusUpdateWindowChanged`."""
        return self.__window_changed

    @property
    def selected_tab_changed(
            self) -> typing.Union[None, FocusUpdateSelectedTabChanged]:
        """
        :returns: `None` if no change to selected tab, otherwise
            :class:`FocusUpdateSelectedTabChanged`."""
        return self.__selected_tab_changed

    @property
    def active_session_changed(
            self) -> typing.Union[None, FocusUpdateActiveSessionChanged]:
        """
        :returns: `None` if no change to active session, otherwise
            :class:`FocusUpdateActiveSessionChanged`."""
        return self.__active_session_changed


class FocusMonitor:
    """An asyncio context manager for monitoring keyboard focus changes.

    :param connection: A connection to iTerm2.

    .. seealso:: Example ":ref:`mrutabs_example`"
    """
    def __init__(self, connection: iterm2.connection.Connection):
        self.__connection = connection
        self.__queue: typing.List[iterm2.api_pb2.FocusChangedNotification] = []
        self.__future: typing.Optional[asyncio.Future] = None
        self.__token = None

    async def __aenter__(self):
        async def async_callback(
                _connection,
                message: iterm2.api_pb2.FocusChangedNotification):
            """Called when focus changes."""
            self.__queue.append(message)
            future = self.__future
            if future is None:
                # Ignore reentrant calls
                return

            self.__future = None
            if future is not None and not future.done():
                temp = self.__queue[0]
                del self.__queue[0]
                future.set_result(temp)

        self.__token = await (
            iterm2.notifications.async_subscribe_to_focus_change_notification(
                self.__connection,
                async_callback))
        return self

    async def __aexit__(self, exc_type, exc, _tb):
        try:
            await iterm2.notifications.async_unsubscribe(
                self.__connection, self.__token)
        except iterm2.notifications.SubscriptionException:
            pass

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
                        print("The active tab is now {}".
                            format(update.selected_tab_changed.tab_id))
        """
        if self.__queue:
            temp = self.__queue[0]
            del self.__queue[0]
            return self.handle_proto(temp)

        future: asyncio.Future = asyncio.Future()
        self.__future = future
        await self.__future
        proto: iterm2.api_pb2.FocusChangedNotification = future.result()
        self.__future = None
        return self.handle_proto(proto)

    # pylint: disable=no-self-use
    def handle_proto(self, proto: iterm2.api_pb2.FocusChangedNotification):
        """Create a FocusUpdate from a protobuf."""
        which = proto.WhichOneof('event')
        if which == 'application_active':
            return FocusUpdate(
                application_active=FocusUpdateApplicationActive(
                    proto.application_active))
        if which == 'window':
            return FocusUpdate(window_changed=FocusUpdateWindowChanged(
                proto.window.window_id,
                FocusUpdateWindowChanged.Reason(proto.window.window_status)))
        if which == 'selected_tab':
            return FocusUpdate(
                selected_tab_changed=FocusUpdateSelectedTabChanged(
                    proto.selected_tab))
        if which == 'session':
            return FocusUpdate(
                active_session_changed=FocusUpdateActiveSessionChanged(
                    proto.session))
        return FocusUpdate()
    # pylint: enable=no-self-use
