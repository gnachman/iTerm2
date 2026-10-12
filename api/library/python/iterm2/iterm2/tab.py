"""Provides a class that represents an iTerm2 tab."""

from __future__ import annotations

import abc
import enum
import json
from typing import TYPE_CHECKING, Any

from . import api_pb2
from .capabilities import (
    AppVersionTooOld,
    check_supports_tab_groups,
    supports_select_pane_in_direction,
)
from .color import Color
from .rpc import (
    RPCException,
    async_activate,
    async_close,
    async_invoke_function,
    async_invoke_method,
    async_set_tab_layout,
    async_variable,
)
from .session import Session, async_invoke_floating_pane_function
from .tabgroup import TabGroup
from .util import invocation_string

if TYPE_CHECKING:
    from collections.abc import Iterable

    from .connection import Connection
    from .session import Splitter
    from .window import Window


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
    class Delegate(abc.ABC):
        """Delegate for Tab."""

        @abc.abstractmethod
        def tab_delegate_get_window(self, tab: Tab) -> Window | None:
            """Returns the Window for a Tab."""
            ...

        @abc.abstractmethod
        async def tab_delegate_get_window_by_id(self, window_id: str) -> Window | None:
            """Returns the Window with the given ID."""
            ...

    # pylint: enable=too-few-public-methods

    delegate: Delegate | None = None

    # pylint: disable=too-many-arguments
    def __init__(
        self,
        connection: Connection,
        tab_id: str,
        root: Splitter,
        tmux_window_id: str | None = None,
        tmux_connection_id: str | None = None,
        minimized_sessions: Iterable[Session] = [],
        tab_group_id: str | None = None,
        tab_group_name: str | None = None,
        tab_group_color: str | None = None,
        tab_group_collapsed: bool = False,
        floating_sessions: Iterable[Session] = [],
        floating_panes_hidden: bool = False,
    ) -> None:
        self.connection: Connection = connection
        self.__tab_id = tab_id
        self.__root = root
        self.__active_session_id: str | None = None
        self.__tmux_window_id = tmux_window_id
        self.__tmux_connection_id = tmux_connection_id
        self.__minimized_sessions = list(minimized_sessions)
        self.__tab_group_id = tab_group_id
        self.__tab_group_name = tab_group_name
        self.__tab_group_color = tab_group_color
        self.__tab_group_collapsed = tab_group_collapsed
        self.__floating_sessions = list(floating_sessions)
        self.__floating_panes_hidden = floating_panes_hidden

    # pylint: enable=too-many-arguments

    def __repr__(self):
        return f"<Tab id={self.__tab_id} sessions={self.sessions}>"

    @property
    def active_session_id(self) -> str | None:
        return self.__active_session_id

    @active_session_id.setter
    def active_session_id(self, active_session_id: str | None) -> None:
        self.__active_session_id = active_session_id

    def update_from(self, other: Tab) -> None:
        """Copies state from another tab into this one."""
        self.__root = other.root
        self.__minimized_sessions = list(other.minimized_sessions)
        self.__floating_sessions = list(other.floating_sessions)
        self.__floating_panes_hidden = other.floating_panes_hidden
        # pylint: disable=protected-access
        self.__tab_group_id = other.__tab_group_id
        self.__tab_group_name = other.__tab_group_name
        self.__tab_group_color = other.__tab_group_color
        self.__tab_group_collapsed = other.__tab_group_collapsed
        # pylint: enable=protected-access

    def update_session(self, session: Session) -> None:
        """Replaces references to a session."""
        if self.__root.update_session(session):
            return
        for sessions in (self.__minimized_sessions, self.__floating_sessions):
            indexes = [
                idx
                for idx, candidate in enumerate(sessions)
                if candidate.session_id == session.session_id
            ]
            if len(indexes) > 0:
                sessions[indexes[0]] = session
                return

    @property
    def window(self) -> Window | None:
        """Returns the window this tab belongs to."""
        assert self.__class__.delegate
        return self.__class__.delegate.tab_delegate_get_window(self)

    @property
    def tab_group(self) -> TabGroup | None:
        """
        The tab group this tab belongs to, or `None` if it is not in a group.

        A tab group is a named, colored collection of adjacent tabs. Its members
        are always kept consecutive in the tab bar; iTerm2 reorders tabs as
        needed to maintain that invariant.

        :returns: A :class:`~iterm2.tabgroup.TabGroup` or `None`.
        """
        if not self.__tab_group_id:
            return None
        color = (
            Color.from_hex(self.__tab_group_color) if (self.__tab_group_color) else None
        )
        return TabGroup(
            self.connection,
            self.__tab_group_id,
            self.__tab_group_name or "",
            color,
            self.__tab_group_collapsed,
        )

    @property
    def tmux_connection_id(self) -> str | None:
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
    def sessions(self) -> list[Session]:
        """
        A tab contains a list of sessions, which are its split panes.

        This excludes minimized sessions and floating panes. Use
        `all_sessions` to get every session in this tab.

        :returns: The sessions belonging to this tab, in no particular order.
        """
        return self.__root.sessions

    @property
    def all_sessions(self) -> list[Session]:
        """
        Returns the visible, minimized and floating sessions in this tab.

        A session would be minimized if another session in the tab is maximized.

        :returns: All sessions in this tab, including minimized sessions and
             floating panes, in no particular order.
        """
        return self.sessions + self.minimized_sessions + self.floating_sessions

    @property
    def root(self) -> Splitter:
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
    def current_session(self) -> Session | None:
        """
        :returns: The active session in this tab or `None` if it could not be
            determined.
        """
        # The active session can be a floating pane, or minimized while a
        # floating pane covers a maximized one.
        for session in self.all_sessions:
            if session.session_id == self.active_session_id:
                return session
        return None

    @property
    def minimized_sessions(self) -> list[Session]:
        """
        :returns: Minimized sessions in this tab. Empty array if none.
        """
        return list(self.__minimized_sessions)

    @property
    def floating_sessions(self) -> list[Session]:
        """
        Sessions in floating panes, which float over the tab's split panes.
        They are not in `root` or `sessions`.

        Requires iTerm2 3.7 or later. Older versions report none.

        :returns: The tab's floating sessions, back to front. Empty if none.
        """
        return list(self.__floating_sessions)

    @property
    def floating_panes_hidden(self) -> bool:
        """
        :returns: Whether the tab's floating panes are hidden.
        """
        return self.__floating_panes_hidden

    def pretty_str(self, indent: str = "") -> str:
        """
        :returns: A human readable description of the tab and its sessions.
        """
        session = f"{indent}Tab id={self.tab_id}\n"
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
        await async_activate(
            self.connection, False, True, order_window_front, tab_id=self.__tab_id
        )

    async def async_select_pane_in_direction(
        self, direction: NavigationDirection
    ) -> str | None:
        """
        Activates a split pane adjacent to the currently selected pane.
        Requires iTerm2 version 3.3.2.

        :param direction: Specifies the direction to move. For example, LEFT
            will cause the pane to the left of the currently active one.
        :returns: The ID of the newly selected session ID, or None if there was
            no session in that direction.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        if not supports_select_pane_in_direction(self.connection):
            raise AppVersionTooOld()

        invocation = invocation_string(
            "iterm2.select_pane_in_direction", {"direction": direction.value}
        )
        return await async_invoke_method(self.connection, self.tab_id, invocation, -1)

    async def async_update_layout(self) -> api_pb2.SetTabLayoutResponse:
        """Adjusts the layout of the sessions in this tab.

        Change the `Session.preferred_size` of any sessions you wish to adjust
        before calling this.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        response = await async_set_tab_layout(
            self.connection, self.tab_id, self.__root.to_protobuf()
        )
        status = response.set_tab_layout_response.status
        # pylint: disable=no-member
        if status == api_pb2.SetTabLayoutResponse.Status.Value("OK"):
            return response.set_tab_layout_response
        raise RPCException(api_pb2.SetTabLayoutResponse.Status.Name(status))

    @property
    def tmux_window_id(self) -> str | None:
        """Returns this tab's tmux window id or None.

        :returns: A tmux window id or `None` if this is not a tmux integration
            window.
        """
        return self.__tmux_window_id

    async def async_set_variable(self, name: str, value: Any) -> None:
        """
        Sets a user-defined variable in the tab.

        See the Scripting Fundamentals documentation for more information on
        user-defined variables.

        :param name: The variable's name. Must begin with `user.`.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await async_variable(
            self.connection, sets=[(name, json.dumps(value))], tab_id=self.__tab_id
        )
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != api_pb2.VariableResponse.Status.Value("OK"):
            raise RPCException(api_pb2.VariableResponse.Status.Name(status))

    async def async_get_variable(self, name: str) -> Any:
        """
        Fetches a tab variable.

        See Badges documentation for more information on variables.

        :param name: The variable's name.

        :returns: The variable's value or `None` if it is undefined.

        :throws: :class:`RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`sorttabs_example`"
        """
        result = await async_variable(
            self.connection, gets=[name], tab_id=self.__tab_id
        )
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != api_pb2.VariableResponse.Status.Value("OK"):
            raise RPCException(api_pb2.VariableResponse.Status.Name(status))
        return json.loads(result.variable_response.values[0])

    async def async_close(self, force: bool = False) -> None:
        """
        Closes the tab.

        :param force: If True, the user will not be prompted for a
            confirmation.

        :throws: :class:`RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`close_to_the_right_example`"
        """
        result = await async_close(self.connection, tabs=[self.__tab_id], force=force)
        status = result.close_response.statuses[0]
        # pylint: disable=no-member
        if status != api_pb2.CloseResponse.Status.Value("OK"):
            raise RPCException(api_pb2.CloseResponse.Status.Name(status))

    async def async_set_title(self, title: str) -> None:
        """Changes the tab's title.

        This is equivalent to editing the tab's title with the menu item Edit
        Tab Title. The title is an interpolated string.

        :param title: The new title. Set it to an empty string to use the
            default value (the current session's title).

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        invocation = invocation_string("iterm2.set_title", {"title": title})
        await async_invoke_method(self.connection, self.tab_id, invocation, -1)

    async def async_invoke_function(self, invocation: str, timeout: float = -1) -> Any:
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
        response = await async_invoke_function(
            self.connection, invocation, tab_id=self.tab_id, timeout=timeout
        )
        which = response.invoke_function_response.WhichOneof("disposition")
        if which == "error":
            # pylint: disable=no-member
            if (
                response.invoke_function_response.error.status
                == api_pb2.InvokeFunctionResponse.Status.Value("TIMEOUT")
            ):
                raise RPCException("Timeout")
            raise RPCException(
                "{}: {}".format(
                    api_pb2.InvokeFunctionResponse.Status.Name(
                        response.invoke_function_response.error.status
                    ),
                    response.invoke_function_response.error.error_reason,
                )
            )
        return json.loads(response.invoke_function_response.success.json_result)

    async def async_create_floating_session(
        self, profile: str | None = None
    ) -> Session:
        """
        Adds a floating pane to this tab. It floats over the split panes,
        centered, and becomes the active session.

        :param profile: The name of the profile to use, or `None` for the
            default profile.

        :returns: The new floating pane's session.

        :throws: :class:`~iterm2.rpc.RPCException` if the pane cannot be
            created, for example because the window's layout is locked.
        """
        args = {"tab_id": self.tab_id}
        if profile is not None:
            args["profile"] = profile
        session_id = await async_invoke_floating_pane_function(
            self.connection, "iterm2.create_floating_pane", args
        )
        assert Session.delegate
        session = await Session.delegate.session_delegate_create_session(session_id)
        if session is None:
            raise RPCException("No such session {}".format(session_id))
        return session

    async def async_move_to_window(self) -> Window:
        """
        Moves this tab to its own window, provided there are multiple tabs in
        the window it belongs to.

        :returns: The new window ID.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        window_id = await self.async_invoke_function("iterm2.move_tab_to_window()")
        assert self.__class__.delegate
        window = await self.__class__.delegate.tab_delegate_get_window_by_id(window_id)
        if not window:
            raise RPCException(f"No such window {window_id}")
        return window

    async def async_add_to_tab_group(self, group: TabGroup) -> None:
        """
        Adds this tab to an existing tab group.

        If the tab already belonged to a different group, it is moved out of
        that group and into this one. iTerm2 reorders tabs so the group's
        members remain consecutive.

        The group must be in the same window as this tab.

        :param group: The :class:`~iterm2.tabgroup.TabGroup` to join.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong (for
            example, if the group is not in this tab's window).
        """
        check_supports_tab_groups(self.connection)
        window = self.window
        if window is None:
            raise RPCException(f"Tab {self.tab_id} is not in a window")
        invocation = invocation_string(
            "iterm2.add_tab_to_group",
            {"tab_id": self.tab_id, "group_id": group.group_id},
        )
        await async_invoke_method(self.connection, window.window_id, invocation, -1)

    async def async_remove_from_tab_group(self) -> None:
        """
        Removes this tab from its tab group, if any.

        iTerm2 moves the tab out of the group so the remaining members stay
        consecutive. If the tab was the group's only member, the group is
        dissolved. This is a no-op if the tab is not in a group.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        check_supports_tab_groups(self.connection)
        window = self.window
        if window is None:
            raise RPCException(f"Tab {self.tab_id} is not in a window")
        invocation = invocation_string(
            "iterm2.remove_tab_from_group", {"tab_id": self.tab_id}
        )
        await async_invoke_method(self.connection, window.window_id, invocation, -1)
