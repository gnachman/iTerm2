"""Provides classes that represent iTerm2 windows."""

from __future__ import annotations

import abc
import json
from typing import TYPE_CHECKING, Any

from . import api_pb2
from .arrangement import SavedArrangementException
from .capabilities import check_supports_tab_groups
from .profile import LocalWriteOnlyProfile, Profile
from .rpc import (
    RPCException,
    async_activate,
    async_close,
    async_create_tab,
    async_get_property,
    async_invoke_function,
    async_invoke_method,
    async_list_sessions,
    async_reorder_tabs,
    async_restore_arrangement,
    async_rpc_create_tmux_window,
    async_save_arrangement,
    async_set_property,
    async_variable,
)
from .session import Session, Splitter
from .tab import Tab
from .tabgroup import TabGroup
from .util import Frame, frame_str, invocation_string

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable, Iterable

    from .color import Color
    from .connection import Connection
    from .tmux import TmuxConnection


class CreateTabException(Exception):
    """Something went wrong creating a tab."""


class CreateWindowException(Exception):
    """A problem was encountered while creating a window."""


class SetPropertyException(Exception):
    """Something went wrong setting a property."""


class GetPropertyException(Exception):
    """Something went wrong fetching a property."""


DELEGATE_FACTORY: Callable[[Connection], Awaitable[Window.Delegate]] | None = None


# pylint: disable=too-many-public-methods
class Window:
    """Represents a terminal window.

    Do not create an instance of `Window` by calling the initializer yourself.
    To get a reference to an existing window, use :class:`~iterm2.app.App` and
    query its `windows` property. To create a new window, use
    :meth:`async_create`.
    """

    class Delegate(abc.ABC):
        """Delegate for Window"""

        @abc.abstractmethod
        async def window_delegate_get_window_with_session_id(
            self, session_id: str
        ) -> Window | None:
            """Gets the Window that contains a Session by ID."""
            ...

        @abc.abstractmethod
        async def window_delegate_get_tab_by_id(self, tab_id: str) -> Tab | None:
            """Gets a Tab by ID."""
            ...

        @abc.abstractmethod
        async def window_delegate_get_tab_with_session_id(
            self, session_id: str
        ) -> Tab | None:
            """Returns the Tab containing a Session by ID."""
            ...

    delegate: Delegate | None = None

    @staticmethod
    async def async_create(
        connection: Connection,
        profile: str | None = None,
        command: str | None = None,
        profile_customizations: LocalWriteOnlyProfile | None = None,
    ) -> Window | None:
        """Creates a new window.

        :param connection: A :class:`~iterm2.connection.Connection`.
        :param profile: The name of the profile to use for the new window.
        :param command: A command to run in lieu of the shell in the new
            session. Mutually exclusive with profile_customizations.
        :param profile_customizations: LocalWriteOnlyProfile giving changes to
            make in profile. Mutually exclusive with command.

        :returns: A new :class:`Window` or `None` if the session ended right
            away.

        :throws: `CreateWindowException` if something went wrong.

        .. seealso:: Example ":ref:`create_window_example`"
        """
        if command is not None:
            lwop = LocalWriteOnlyProfile()
            lwop.set_use_custom_command(Profile.USE_CUSTOM_COMMAND_ENABLED)
            lwop.set_command(command)
            custom_dict = lwop.values
        elif profile_customizations is not None:
            custom_dict = profile_customizations.values
        else:
            custom_dict = None

        result = await async_create_tab(
            connection, profile=profile, window=None, profile_customizations=custom_dict
        )
        ctr = result.create_tab_response
        # pylint: disable=no-member
        if ctr.status == api_pb2.CreateTabResponse.Status.Value("OK"):
            if not Window.delegate:
                return await Window._async_load(connection, ctr.window_id)

            assert Window.delegate
            return await Window.delegate.window_delegate_get_window_with_session_id(
                ctr.session_id
            )

        # pylint: disable=no-member
        raise CreateWindowException(
            api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status)
        )

    @staticmethod
    async def _async_load(connection: Connection, window_id: str):
        response = await async_list_sessions(connection)
        list_sessions_response = response.list_sessions_response
        for window in list_sessions_response.windows:
            if window.window_id == window_id:
                return Window.create_from_proto(connection, window)
        return None

    @staticmethod
    def create_from_proto(
        connection: Connection, window: api_pb2.ListSessionsResponse.Window
    ) -> Window | None:
        """Creates a new instance from a protobuf."""
        tabs: list[Tab] = []
        for tab in window.tabs:
            root = Splitter.from_node(tab.root, connection)
            if tab.HasField("tmux_window_id"):
                tmux_window_id = tab.tmux_window_id
            else:
                tmux_window_id = None
            minimized_sessions = [
                Session(connection, None, summary)
                for summary in (tab.minimized_sessions or [])
            ]
            floating_sessions = [
                Session(connection, None, floating_pane.session, floating=True)
                for floating_pane in (tab.floating_panes or [])
            ]
            new_tab = Tab(
                connection,
                tab.tab_id,
                root,
                tmux_window_id,
                tab.tmux_connection_id,
                minimized_sessions,
                tab.tab_group_id if tab.HasField("tab_group_id") else None,
                tab.tab_group_name if tab.HasField("tab_group_name") else None,
                tab.tab_group_color if tab.HasField("tab_group_color") else None,
                tab.tab_group_collapsed
                if tab.HasField("tab_group_collapsed")
                else None,  # type: ignore[arg-type]
                floating_sessions,
                tab.floating_panes_hidden,
            )
            # protocol 1.18+ reports the active session here, so current_session
            # is correct straight from a list-sessions refresh without waiting
            # for a focus notification. Older servers leave it unset.
            if tab.HasField("active_session_id"):
                new_tab.active_session_id = tab.active_session_id
            tabs.append(new_tab)

        if not tabs:
            return None

        new_window = Window(
            connection, window.window_id, tabs, window.frame, window.number
        )
        # protocol 1.18+ reports the selected tab here, so current_tab is
        # correct straight from a list-sessions refresh without waiting for a
        # focus notification. Older servers leave it unset.
        if window.HasField("selected_tab_id"):
            new_window.selected_tab_id = window.selected_tab_id
        return new_window

    # pylint: disable=too-many-arguments
    def __init__(
        self,
        connection: Connection,
        window_id: str,
        tabs: list[Tab],
        frame: api_pb2.Frame,
        number: int,
    ) -> None:
        self.connection: Connection = connection
        self.__window_id = window_id
        self.__tabs = tabs
        self.frame = frame
        self.__number = number
        # None means unknown. Can get set later.
        self.selected_tab_id: str | None = None

    def __repr__(self):
        return (
            f"<Window id={self.__window_id} tabs={self.__tabs} "
            f"frame={frame_str(self.frame)}>"
        )

    def update_from(self, other: Window) -> None:
        """Copies state from other window to this one."""
        self.__tabs = other.tabs
        self.frame = other.frame

    def update_tab(self, tab: Tab) -> None:
        """Replace references to a tab."""
        for i, old_tab in enumerate(self.__tabs):
            if old_tab.tab_id == tab.tab_id:
                self.__tabs[i] = tab
                return

    def pretty_str(self, indent: str = "") -> str:
        """
        :returns: A nicely formatted string describing the window, its tabs,
            and their sessions.
        """
        session = indent + f"Window id={self.window_id} frame={frame_str(self.frame)}\n"
        for tab in self.__tabs:
            session += tab.pretty_str(indent=indent + "  ")
        return session

    @property
    def window_number(self) -> int:
        """
        :returns: The window's number. When less than 10, this is the number
            part of the shortcut to switch to the window.
        """
        return self.__number

    @property
    def window_id(self) -> str:
        """
        :returns: the window's unique identifier.
        """
        return self.__window_id

    @property
    def tabs(self) -> list[Tab]:
        """
        :returns: a list of iterm2.tab.Tab objects.
        """
        return self.__tabs

    async def async_set_tabs(self, tabs: Iterable[Tab]) -> None:
        """Changes the tabs and their order.

        The provided tabs may belong to any window. They will be moved if
        needed. Windows entirely denuded of tabs will be closed.

        All provided tabs will be inserted in the given order starting at the
        first positions. Any tabs already belonging to this window not in the
        list will remain after the provided tabs.

        :param tabs: a list of tabs, forming the new set of tabs in this
            window.
        :throws: RPCException if something goes wrong.

        .. seealso::
            * Example ":ref:`movetab_example`"
            * Example ":ref:`mrutabs_example`"
            * Example ":ref:`sorttabs_example`"
        """
        tab_ids = (tab.tab_id for tab in tabs)
        await async_reorder_tabs(
            self.connection, assignments=[(self.window_id, tab_ids)]
        )

    @property
    def tab_groups(self) -> list[TabGroup]:
        """
        The distinct tab groups in this window, in tab order.

        A tab group is a named, colored collection of adjacent tabs.

        :returns: A list of :class:`~iterm2.tabgroup.TabGroup`.
        """
        result: list[TabGroup] = []
        seen: set[str] = set()
        for tab in self.__tabs:
            group = tab.tab_group
            if group is None or group.group_id in seen:
                continue
            seen.add(group.group_id)
            result.append(group)
        return result

    async def async_create_tab_group(
        self, name: str, tabs: Iterable[Tab], color: Color | None = None
    ) -> TabGroup:
        """
        Creates a new tab group from the given tabs.

        All tabs must belong to this window. A tab already in another group is
        moved into the new one. iTerm2 reorders tabs so the new group's members
        are consecutive.

        :param name: The name for the new group.
        :param tabs: The tabs to place in the group. Must be non-empty and all
            in this window.
        :param color: The group's color, or `None` to have iTerm2 pick one.

        :returns: The newly created :class:`~iterm2.tabgroup.TabGroup`. Its
            `color` is `None` when iTerm2 picked one automatically; re-fetch the
            app to observe the assigned color.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong (for
            example, if a tab is not in this window).
        """
        check_supports_tab_groups(self.connection)
        invocation = invocation_string(
            "iterm2.create_tab_group",
            {
                "tab_ids": [tab.tab_id for tab in tabs],
                "name": name,
                "color": color.hex if color else "",
            },
        )
        group_id = await async_invoke_method(
            self.connection, self.__window_id, invocation, -1
        )
        return TabGroup(self.connection, group_id, name, color, False)

    @property
    def current_tab(self) -> Tab | None:
        """
        :returns: The current tab in this window or `None` if it could not be
            determined.
        """
        for tab in self.__tabs:
            if tab.tab_id == self.selected_tab_id:
                return tab
        return None

    async def async_create_tmux_tab(
        self, tmux_connection: TmuxConnection
    ) -> Tab | None:
        """Creates a new tmux tab in this window.

        This may not be called from within a
        :class:`~iterm2.transaction.Transaction`.

        :param tmux_connection: The tmux connection to own the new tab.

        :returns: A newly created tab, or `None` if it could not be created.

        :throws: `CreateTabException` if something went wrong.

        .. seealso:: Example ":ref:`tmux_example`"
        """
        tmux_window_id = f"{-(self.__number + 1)}"
        response = await async_rpc_create_tmux_window(
            self.connection, tmux_connection.connection_id, tmux_window_id
        )
        # pylint: disable=no-member
        if response.tmux_response.status != api_pb2.TmuxResponse.Status.Value("OK"):
            raise CreateTabException(
                api_pb2.TmuxResponse.Status.Name(response.tmux_response.status)
            )
        tab_id = response.tmux_response.create_window.tab_id
        if not Window.delegate:
            assert DELEGATE_FACTORY
            Window.delegate = await DELEGATE_FACTORY(self.connection)
        return await Window.delegate.window_delegate_get_tab_by_id(tab_id)

    async def async_create_tab(
        self,
        profile: str | None = None,
        command: str | None = None,
        index: int | None = None,
        profile_customizations: LocalWriteOnlyProfile | None = None,
        select: bool = True,
    ) -> Tab | None:
        """
        Creates a new tab in this window.

        :param profile: The profile name to use or None for the default
            profile.
        :param command: The command to run in the new session, or None for the
            default for the profile. Mutually exclusive with
            profile_customizations.
        :param index: The index in the window where the new tab should go
            (0=first position, etc.)
        :param profile_customizations: LocalWriteOnlyProfile giving changes to
            make in profile. Mutually exclusive with command.
        :param select: If True (the default), select the new tab and order this
            window to the front. If False, create the tab in the background
            without moving keyboard focus.

        :returns: :class:`Tab` or `None` if the session closed right away.

        :throws: CreateTabException if something goes wrong.
        """
        if command is not None:
            lwop = LocalWriteOnlyProfile()
            lwop.set_use_custom_command(Profile.USE_CUSTOM_COMMAND_ENABLED)
            lwop.set_command(command)
            custom_dict = lwop.values
        elif profile_customizations is not None:
            custom_dict = profile_customizations.values
        else:
            custom_dict = None
        result = await async_create_tab(
            self.connection,
            profile=profile,
            window=self.__window_id,
            index=index,
            profile_customizations=custom_dict,
            select=select,
        )
        # pylint: disable=no-member
        if result.create_tab_response.status == api_pb2.CreateTabResponse.Status.Value(
            "OK"
        ):
            session_id = result.create_tab_response.session_id
            assert Window.delegate
            return await Window.delegate.window_delegate_get_tab_with_session_id(
                session_id
            )
        # pylint: disable=no-member
        raise CreateTabException(
            api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status)
        )

    async def async_get_frame(self) -> Frame:
        """
        Gets the window's frame.

        The origin (0,0) is the *bottom* right of the main screen.

        :returns: This window's frame. This includes window decoration such as
            the title bar.

        :throws: :class:`GetPropertyException` if something goes wrong.
        """

        response = await async_get_property(self.connection, "frame", self.__window_id)
        status = response.get_property_response.status
        # pylint: disable=no-member
        if status == api_pb2.GetPropertyResponse.Status.Value("OK"):
            frame_dict = json.loads(response.get_property_response.json_value)
            frame = Frame()
            frame.load_from_dict(frame_dict)
            return frame
        raise GetPropertyException(response.get_property_response.status)

    async def async_set_frame(self, frame: Frame) -> None:
        """
        Sets the window's frame.

        :param frame: The desired frame.

        :throws: :class:`SetPropertyException` if something goes wrong.
        """
        json_value = json.dumps(frame.dict)
        response = await async_set_property(
            self.connection, "frame", json_value, window_id=self.__window_id
        )
        status = response.set_property_response.status
        # pylint: disable=no-member
        if status != api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.get_property_response.status)

    async def async_get_fullscreen(self) -> bool:
        """
        Checks if the window is full-screen.

        :returns: Whether the window is full screen.

        :throws: :class:`GetPropertyException` if something goes wrong.
        """
        response = await async_get_property(
            self.connection, "fullscreen", self.__window_id
        )
        status = response.get_property_response.status
        # pylint: disable=no-member
        if status == api_pb2.GetPropertyResponse.Status.Value("OK"):
            return json.loads(response.get_property_response.json_value)
        raise GetPropertyException(response.get_property_response.status)

    async def async_set_fullscreen(self, fullscreen: bool) -> None:
        """
        Changes the window's full-screen status.

        :param fullscreen: Whether you wish the window to be full screen.

        :throws: :class:`SetPropertyException` if something goes wrong (such as
            that the fullscreen status could not be changed).
        """
        json_value = json.dumps(fullscreen)
        response = await async_set_property(
            self.connection, "fullscreen", json_value, window_id=self.__window_id
        )
        status = response.set_property_response.status
        # pylint: disable=no-member
        if status != api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.set_property_response.status)

    async def async_activate(self) -> None:
        """
        Gives the window keyboard focus and orders it to the front.

        Note that this won't activate the app. Use the :meth:`async_activate`
        method on :class:`~iterm2.app.App` to activate the app. You'll probably
        want to call both methods.
        """
        await async_activate(
            self.connection, False, False, True, window_id=self.__window_id
        )

    async def async_close(self, force: bool = False) -> None:
        """
        Closes the window.

        :param force: If `True`, the user will not be prompted for a
            confirmation.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await async_close(
            self.connection, windows=[self.__window_id], force=force
        )
        status = result.close_response.statuses[0]
        # pylint: disable=no-member
        if status != api_pb2.CloseResponse.Status.Value("OK"):
            raise RPCException(api_pb2.CloseResponse.Status.Name(status))

    async def async_save_window_as_arrangement(self, name: str) -> None:
        """Save the current window as a new arrangement.

        :param name: The name to save as. Will overwrite if one already exists
            with this name.
        """
        result = await async_save_arrangement(self.connection, name, self.__window_id)
        # pylint: disable=no-member
        if result.create_tab_response.status != api_pb2.CreateTabResponse.Status.Value(
            "OK"
        ):
            raise SavedArrangementException(
                api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status
                )
            )

    async def async_restore_window_arrangement(self, name: str) -> None:
        """Restore a window arrangement as tabs in this window.

        :param name: The name to restore.

        :throws: :class:`~iterm2.arrangement.SavedArrangementException` if the
            named arrangement does not exist."""
        result = await async_restore_arrangement(
            self.connection, name, self.__window_id
        )
        # pylint: disable=no-member
        if result.create_tab_response.status != api_pb2.CreateTabResponse.Status.Value(
            "OK"
        ):
            raise SavedArrangementException(
                api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status
                )
            )

    async def async_get_variable(self, name: str) -> Any:
        """
        Fetches a window variable.

        See the Scripting Fundamentals documentation for more information on
        variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        # pylint: disable=no-member
        result = await async_variable(
            self.connection, window_id=self.__window_id, gets=[name]
        )
        status = result.variable_response.status
        if status != api_pb2.VariableResponse.Status.Value("OK"):
            raise RPCException(api_pb2.VariableResponse.Status.Name(status))
        return json.loads(result.variable_response.values[0])

    async def async_set_variable(self, name: str, value: Any) -> None:
        """
        Sets a user-defined variable in the window.

        See the Scripting Fundamentals documentation for more information on
        user-defined variables.

        :param name: The variable's name. Must begin with `user.`.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        # pylint: disable=no-member
        result = await async_variable(
            self.connection, sets=[(name, json.dumps(value))], window_id=self.window_id
        )
        status = result.variable_response.status
        if status != api_pb2.VariableResponse.Status.Value("OK"):
            raise RPCException(api_pb2.VariableResponse.Status.Name(status))

    async def async_set_title(self, title: str) -> None:
        """Changes the window's title.

        This is equivalent to editing the window's title with the menu item
        Edit Window Title. The title is an interpolated string. Note that when
        using tmux integration, tab titles correspond to tmux window titles.
        iTerm2's window titles have no equivalent in tmux.

        :param title: The new title. Set it to an empty string to use the
            default value (the current tab's title).

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        invocation = invocation_string("iterm2.set_title", {"title": title})
        await async_invoke_method(self.connection, self.window_id, invocation, -1)

    async def async_invoke_function(self, invocation: str, timeout: float = -1) -> Any:
        """
        Invoke an RPC. Could be a registered function by this or another script
        of a built-in function.

        This invokes the RPC in the context of this window. Note that most
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
            self.connection, invocation, window_id=self.window_id, timeout=timeout
        )
        which = response.invoke_function_response.WhichOneof("disposition")
        # pylint: disable=no-member
        if which == "error":
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
