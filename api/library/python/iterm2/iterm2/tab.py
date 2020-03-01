"""Provides a class that represents an iTerm2 tab."""
import abc
import enum
import json
import typing

import iterm2.api_pb2
import iterm2.capabilities
import iterm2.rpc
import iterm2.session
import iterm2.util


class NavigationDirection(enum.Enum):
    """Cardinal directions."""
    LEFT = "left"
    RIGHT = "right"
    ABOVE = "above"
    BELOW = "below"


class Tab:
    """Represents a tab.

    Don't create this yourself. Instead, use :class:`~iterm2.App`."""

    # pylint: disable=too-few-public-methods
    class Delegate:
        """Delegate for Tab."""
        @abc.abstractmethod
        def tab_delegate_get_window(
                self, tab: 'Tab') -> typing.Optional['iterm2.window.Window']:
            """Returns the Window for a Tab."""

        @abc.abstractmethod
        async def tab_delegate_get_window_by_id(
                self,
                window_id: str) -> typing.Optional['iterm2.window.Window']:
            """Returns the Window with the given ID."""
    # pylint: enable=too-few-public-methods

    delegate: typing.Optional[Delegate] = None

    # pylint: disable=too-many-arguments
    def __init__(
            self,
            connection,
            tab_id,
            root,
            tmux_window_id=None,
            tmux_connection_id=None):
        self.connection = connection
        self.__tab_id = tab_id
        self.__root = root
        self.__active_session_id = None
        self.__tmux_window_id = tmux_window_id
        self.__tmux_connection_id = tmux_connection_id
    # pylint: enable=too-many-arguments

    def __repr__(self):
        return "<Tab id=%s sessions=%s>" % (self.__tab_id, self.sessions)

    @property
    def active_session_id(self):
        return self.__active_session_id

    @active_session_id.setter
    def active_session_id(self, active_session_id):
        self.__active_session_id = active_session_id

    def update_from(self, other):
        """Copies state from another tab into this one."""
        self.__root = other.root

    def update_session(self, session):
        """Replaces references to a session."""
        self.__root.update_session(session)

    @property
    def window(self) -> typing.Optional['iterm2.window.Window']:
        """Returns the window this tab belongs to."""
        assert self.__class__.delegate
        return self.__class__.delegate.tab_delegate_get_window(self)

    @property
    def tmux_connection_id(self):
        """Returns the connection ID."""
        return self.__tmux_connection_id

    @property
    def tab_id(self) -> str:
        """
        Each tab has a globally unique identifier.

        :returns: The tab's identifier, a string.
        """
        return self.__tab_id

    @property
    def sessions(self) -> typing.List['iterm2.session.Session']:
        """
        A tab contains a list of sessions, which are its split panes.

        :returns: The sessions belonging to this tab, in no particular order.
        """
        return self.__root.sessions

    @property
    def root(self) -> iterm2.session.Splitter:
        """
        A tab's sessions are stored in a tree. This returns the root of that
        tree.

        An interior node of the tree is a Splitter. That corresponds to a
        collection of adjacent sessions with split pane dividers that are all
        either vertical or horizontal.

        Leaf nodes are Sessions.

        :returns: The root of the session tree.
        """
        return self.__root

    @property
    def current_session(self) -> typing.Union[None, iterm2.session.Session]:
        """
        :returns: The active session in this tab or `None` if it could not be
            determined.
        """
        for session in self.sessions:
            if session.session_id == self.active_session_id:
                return session
        return None

    def pretty_str(self, indent: str = "") -> str:
        """
        :returns: A human readable description of the tab and its sessions.
        """
        session = indent + "Tab id=%s\n" % self.tab_id
        session += self.__root.pretty_str(indent=indent + "  ")
        return session

    async def async_select(self, order_window_front: bool = True) -> None:
        """Deprecated in favor of `async_activate`."""
        await self.async_activate(order_window_front)

    async def async_activate(self, order_window_front: bool = True) -> None:
        """
        Selects this tab.

        :param order_window_front: Whether the window this session is in should
            be brought to the front and given keyboard focus.

        .. seealso:: Example ":ref:`function_key_tabs_example`"
        """
        await iterm2.rpc.async_activate(
            self.connection,
            False,
            True,
            order_window_front,
            tab_id=self.__tab_id)

    async def async_select_pane_in_direction(
            self, direction: NavigationDirection) -> typing.Optional[str]:
        """
        Activates a split pane adjacent to the currently selected pane.
        Requires iTerm2 version 3.3.2.

        :param direction: Specifies the direction to move. For example, LEFT
            will cause the pane to the left of the currently active one.
        :returns: The ID of the newly selected session ID, or None if there was
            no session in that direction.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        if not iterm2.capabilities.supports_select_pane_in_direction(
                self.connection):
            raise iterm2.capabilities.AppVersionTooOld()

        invocation = iterm2.util.invocation_string(
            "iterm2.select_pane_in_direction",
            {"direction": direction.value})
        return await iterm2.rpc.async_invoke_method(
            self.connection, self.tab_id, invocation, -1)

    async def async_update_layout(self) -> None:
        """Adjusts the layout of the sessions in this tab.

        Change the `Session.preferred_size` of any sessions you wish to adjust
        before calling this.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        response = await iterm2.rpc.async_set_tab_layout(
            self.connection, self.tab_id, self.__root.to_protobuf())
        status = response.set_tab_layout_response.status
        # pylint: disable=no-member
        if status == iterm2.api_pb2.SetTabLayoutResponse.Status.Value("OK"):
            return response.set_tab_layout_response
        raise iterm2.rpc.RPCException(
            iterm2.api_pb2.SetTabLayoutResponse.Status.Name(status))

    @property
    def tmux_window_id(self) -> typing.Union[None, str]:
        """Returns this tab's tmux window id or None.

        :returns: A tmux window id or `None` if this is not a tmux integration
            window.
        """
        return self.__tmux_window_id

    async def async_set_variable(self, name: str, value: typing.Any) -> None:
        """
        Sets a user-defined variable in the tab.

        See the Scripting Fundamentals documentation for more information on
        user-defined variables.

        :param name: The variable's name. Must begin with `user.`.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(
            self.connection,
            sets=[(name, json.dumps(value))],
            tab_id=self.__tab_id)
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_get_variable(self, name: str) -> typing.Any:
        """
        Fetches a tab variable.

        See Badges documentation for more information on variables.

        :param name: The variable's name.

        :returns: The variable's value or `None` if it is undefined.

        :throws: :class:`RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`sorttabs_example`"
        """
        result = await iterm2.rpc.async_variable(
            self.connection, gets=[name], tab_id=self.__tab_id)
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))
        return json.loads(result.variable_response.values[0])

    async def async_close(self, force: bool = False) -> None:
        """
        Closes the tab.

        :param force: If True, the user will not be prompted for a
            confirmation.

        :throws: :class:`RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`close_to_the_right_example`"
        """
        result = await iterm2.rpc.async_close(
            self.connection, tabs=[self.__tab_id], force=force)
        status = result.close_response.statuses[0]
        # pylint: disable=no-member
        if status != iterm2.api_pb2.CloseResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.CloseResponse.Status.Name(status))

    async def async_set_title(self, title: str):
        """Changes the tab's title.

        This is equivalent to editing the tab's title with the menu item Edit
        Tab Title. The title is an interpolated string.

        :param title: The new title. Set it to an empty string to use the
            default value (the current session's title).

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        invocation = iterm2.util.invocation_string(
            "iterm2.set_title",
            {"title": title})
        await iterm2.rpc.async_invoke_method(
            self.connection, self.tab_id, invocation, -1)

    async def async_invoke_function(
            self, invocation: str, timeout: float = -1):
        """
        Invoke an RPC. Could be a registered function by this or another script
        of a built-in function.

        This invokes the RPC in the context of this tab. Note that most
        user-defined RPCs expect to be invoked in the context of a session.
        Default variables will be pulled from that scope. If you call a
        function from the wrong context it may fail because its defaults will
        not be set properly.

        :param invocation: A function invocation string.
        :param timeout: Max number of secondsto wait. Negative values mean to
            use the system default timeout.

        :returns: The result of the invocation if successful.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        response = await iterm2.rpc.async_invoke_function(
            self.connection,
            invocation,
            tab_id=self.tab_id,
            timeout=timeout)
        which = response.invoke_function_response.WhichOneof('disposition')
        if which == 'error':
            # pylint: disable=no-member
            if (response.invoke_function_response.error.status ==
                    iterm2.api_pb2.InvokeFunctionResponse.Status.
                    Value("TIMEOUT")):
                raise iterm2.rpc.RPCException("Timeout")
            raise iterm2.rpc.RPCException("{}: {}".format(
                iterm2.api_pb2.InvokeFunctionResponse.Status.Name(
                    response.invoke_function_response.error.status),
                response.invoke_function_response.error.error_reason))
        return json.loads(
            response.invoke_function_response.success.json_result)

    async def async_move_to_window(self) -> 'iterm2.window.Window':
        """
        Moves this tab to its own window, provided there are multiple tabs in
        the window it belongs to.

        :returns: The new window ID.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        window_id = await self.async_invoke_function(
            "iterm2.move_tab_to_window()")
        assert self.__class__.delegate
        window = await self.__class__.delegate.tab_delegate_get_window_by_id(
            window_id)
        if not window:
            raise iterm2.rpc.RPCException(
                "No such window {}".format(window_id))
        return window
