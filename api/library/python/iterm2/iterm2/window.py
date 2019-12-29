"""Provides classes that represent iTerm2 windows."""
import abc
import json
import typing

import iterm2.api_pb2
import iterm2.arrangement
import iterm2.connection
import iterm2.profile
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.transaction
import iterm2.util


class CreateTabException(Exception):
    """Something went wrong creating a tab."""


class CreateWindowException(Exception):
    """A problem was encountered while creating a window."""


class SetPropertyException(Exception):
    """Something went wrong setting a property."""


class GetPropertyException(Exception):
    """Something went wrong fetching a property."""


DELEGATE_FACTORY: typing.Optional[
    typing.Callable[
        [iterm2.connection.Connection],
        typing.Awaitable['Window.Delegate']]] = None


# pylint: disable=too-many-public-methods
class Window:
    """Represents a terminal window.

    Do not create an instance of `Window` by calling the initializer yourself.
    To get a reference to an existing window, use :class:`~iterm2.app.App` and
    query its `windows` property. To create a new window, use
    :meth:`async_create`.
    """

    class Delegate:
        """Delegate for Window"""
        @abc.abstractmethod
        async def window_delegate_get_window_with_session_id(
                self,
                session_id: str) -> typing.Optional['Window']:
            """Gets the Window that contains a Session by ID."""

        @abc.abstractmethod
        async def window_delegate_get_tab_by_id(
                self,
                tab_id: str) -> typing.Optional[iterm2.tab.Tab]:
            """Gets a Tab by ID."""

        @abc.abstractmethod
        async def window_delegate_get_tab_with_session_id(
                self,
                session_id: str) -> typing.Optional[iterm2.tab.Tab]:
            """Returns the Tab containing a Session by ID."""

    delegate: typing.Optional[Delegate] = None

    @staticmethod
    async def async_create(
            connection: iterm2.connection.Connection,
            profile: str = None,
            command: str = None,
            profile_customizations:
            iterm2.profile.LocalWriteOnlyProfile = None) -> typing.Optional[
                'Window']:
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
            lwop = iterm2.profile.LocalWriteOnlyProfile()
            lwop.set_use_custom_command(
                iterm2.profile.Profile.USE_CUSTOM_COMMAND_ENABLED)
            lwop.set_command(command)
            custom_dict = lwop.values
        elif profile_customizations is not None:
            custom_dict = profile_customizations.values
        else:
            custom_dict = None

        result = await iterm2.rpc.async_create_tab(
            connection,
            profile=profile,
            window=None,
            profile_customizations=custom_dict)
        ctr = result.create_tab_response
        # pylint: disable=no-member
        if ctr.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            if not Window.delegate:
                return await Window._async_load(connection, ctr.window_id)

            assert Window.delegate
            return await (
                Window.delegate.window_delegate_get_window_with_session_id(
                    ctr.session_id))

        # pylint: disable=no-member
        raise CreateWindowException(
            iterm2.api_pb2.CreateTabResponse.Status.Name(
                result.create_tab_response.status))

    @staticmethod
    async def _async_load(connection, window_id):
        response = await iterm2.rpc.async_list_sessions(connection)
        list_sessions_response = response.list_sessions_response
        for window in list_sessions_response.windows:
            if window.window_id == window_id:
                return Window.create_from_proto(connection, window)
        return None

    @staticmethod
    def create_from_proto(connection, window):
        """Creates a new instance from a protobuf."""
        tabs = []
        for tab in window.tabs:
            root = iterm2.session.Splitter.from_node(tab.root, connection)
            if tab.HasField("tmux_window_id"):
                tmux_window_id = tab.tmux_window_id
            else:
                tmux_window_id = None
            tabs.append(
                iterm2.tab.Tab(
                    connection,
                    tab.tab_id,
                    root,
                    tmux_window_id,
                    tab.tmux_connection_id))

        if not tabs:
            return None

        return iterm2.window.Window(
            connection,
            window.window_id,
            tabs,
            window.frame,
            window.number)

    # pylint: disable=too-many-arguments
    def __init__(self, connection, window_id, tabs, frame, number):
        self.connection = connection
        self.__window_id = window_id
        self.__tabs = tabs
        self.frame = frame
        self.__number = number
        # None means unknown. Can get set later.
        self.selected_tab_id = None

    def __repr__(self):
        return "<Window id=%s tabs=%s frame=%s>" % (
            self.__window_id,
            self.__tabs,
            iterm2.util.frame_str(self.frame))

    def update_from(self, other):
        """Copies state from other window to this one."""
        self.__tabs = other.tabs
        self.frame = other.frame

    def update_tab(self, tab):
        """Replace references to a tab."""
        i = 0
        for old_tab in self.__tabs:
            if old_tab.tab_id == tab.tab_id:
                self.__tabs[i] = tab
                return
            i += 1

    def pretty_str(self, indent: str = "") -> str:
        """
        :returns: A nicely formatted string describing the window, its tabs,
            and their sessions.
        """
        session = indent + "Window id=%s frame=%s\n" % (
            self.window_id, iterm2.util.frame_str(self.frame))
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
    def tabs(self) -> typing.List[iterm2.tab.Tab]:
        """
        :returns: a list of iterm2.tab.Tab objects.
        """
        return self.__tabs

    async def async_set_tabs(self, tabs: typing.List[iterm2.tab.Tab]):
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
        tab_ids = map(lambda tab: tab.tab_id, tabs)
        await iterm2.rpc.async_reorder_tabs(
            self.connection,
            assignments=[(self.window_id, tab_ids)])

    @property
    def current_tab(self) -> typing.Optional[iterm2.tab.Tab]:
        """
        :returns: The current tab in this window or `None` if it could not be
            determined.
        """
        for tab in self.__tabs:
            if tab.tab_id == self.selected_tab_id:
                return tab
        return None

    async def async_create_tmux_tab(
            self,
            tmux_connection:
            'iterm2.tmux.TmuxConnection') -> typing.Optional[iterm2.tab.Tab]:
        """Creates a new tmux tab in this window.

        This may not be called from within a
        :class:`~iterm2.transaction.Transaction`.

        :param tmux_connection: The tmux connection to own the new tab.

        :returns: A newly created tab, or `None` if it could not be created.

        :throws: `CreateTabException` if something went wrong.

        .. seealso:: Example ":ref:`tmux_example`"
        """
        tmux_window_id = "{}".format(-(self.__number + 1))
        response = await iterm2.rpc.async_rpc_create_tmux_window(
            self.connection,
            tmux_connection.connection_id,
            tmux_window_id)
        # pylint: disable=no-member
        if (response.tmux_response.status !=
                iterm2.api_pb2.TmuxResponse.Status.Value("OK")):
            raise CreateTabException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))
        tab_id = response.tmux_response.create_window.tab_id
        if not Window.delegate:
            assert DELEGATE_FACTORY
            Window.delegate = await DELEGATE_FACTORY(self.connection)
        return await Window.delegate.window_delegate_get_tab_by_id(tab_id)

    async def async_create_tab(
            self,
            profile: typing.Optional[str] = None,
            command: typing.Optional[str] = None,
            index: typing.Optional[int] = None,
            profile_customizations: typing.Optional[
                iterm2.profile.LocalWriteOnlyProfile] = None) -> typing.Optional[
                    iterm2.tab.Tab]:
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

        :returns: :class:`Tab` or `None` if the session closed right away.

        :throws: CreateTabException if something goes wrong.
        """
        if command is not None:
            lwop = iterm2.profile.LocalWriteOnlyProfile()
            lwop.set_use_custom_command(
                iterm2.profile.Profile.USE_CUSTOM_COMMAND_ENABLED)
            lwop.set_command(command)
            custom_dict = lwop.values
        elif profile_customizations is not None:
            custom_dict = profile_customizations.values
        else:
            custom_dict = None
        result = await iterm2.rpc.async_create_tab(
            self.connection,
            profile=profile,
            window=self.__window_id,
            index=index,
            profile_customizations=custom_dict)
        # pylint: disable=no-member
        if (result.create_tab_response.status ==
                iterm2.api_pb2.CreateTabResponse.Status.Value("OK")):
            session_id = result.create_tab_response.session_id
            assert Window.delegate
            return await Window.delegate.window_delegate_get_tab_with_session_id(
                session_id)
        # pylint: disable=no-member
        raise CreateTabException(
            iterm2.api_pb2.CreateTabResponse.Status.Name(
                result.create_tab_response.status))

    async def async_get_frame(self) -> iterm2.util.Frame:
        """
        Gets the window's frame.

        The origin (0,0) is the *bottom* right of the main screen.

        :returns: This window's frame. This includes window decoration such as
            the title bar.

        :throws: :class:`GetPropertyException` if something goes wrong.
        """

        response = await iterm2.rpc.async_get_property(
            self.connection, "frame", self.__window_id)
        status = response.get_property_response.status
        # pylint: disable=no-member
        if status == iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"):
            frame_dict = json.loads(response.get_property_response.json_value)
            frame = iterm2.util.Frame()
            frame.load_from_dict(frame_dict)
            return frame
        raise GetPropertyException(response.get_property_response.status)

    async def async_set_frame(self, frame: iterm2.util.Frame) -> None:
        """
        Sets the window's frame.

        :param frame: The desired frame.

        :throws: :class:`SetPropertyException` if something goes wrong.
        """
        json_value = json.dumps(frame.dict)
        response = await iterm2.rpc.async_set_property(
            self.connection,
            "frame",
            json_value,
            window_id=self.__window_id)
        status = response.set_property_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.get_property_response.status)

    async def async_get_fullscreen(self) -> bool:
        """
        Checks if the window is full-screen.

        :returns: Whether the window is full screen.

        :throws: :class:`GetPropertyException` if something goes wrong.
        """
        response = await iterm2.rpc.async_get_property(
            self.connection, "fullscreen", self.__window_id)
        status = response.get_property_response.status
        # pylint: disable=no-member
        if status == iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"):
            return json.loads(response.get_property_response.json_value)
        raise GetPropertyException(response.get_property_response.status)

    async def async_set_fullscreen(self, fullscreen: bool):
        """
        Changes the window's full-screen status.

        :param fullscreen: Whether you wish the window to be full screen.

        :throws: :class:`SetPropertyException` if something goes wrong (such as
            that the fullscreen status could not be changed).
        """
        json_value = json.dumps(fullscreen)
        response = await iterm2.rpc.async_set_property(
            self.connection,
            "fullscreen",
            json_value,
            window_id=self.__window_id)
        status = response.set_property_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.set_property_response.status)

    async def async_activate(self) -> None:
        """
        Gives the window keyboard focus and orders it to the front.
        """
        await iterm2.rpc.async_activate(
            self.connection,
            False,
            False,
            True,
            window_id=self.__window_id)

    async def async_close(self, force: bool = False):
        """
        Closes the window.

        :param force: If `True`, the user will not be prompted for a
            confirmation.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_close(
            self.connection, windows=[self.__window_id], force=force)
        status = result.close_response.statuses[0]
        # pylint: disable=no-member
        if status != iterm2.api_pb2.CloseResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.CloseResponse.Status.Name(status))

    async def async_save_window_as_arrangement(self, name: str) -> None:
        """Save the current window as a new arrangement.

        :param name: The name to save as. Will overwrite if one already exists
            with this name.
        """
        result = await iterm2.rpc.async_save_arrangement(
            self.connection, name, self.__window_id)
        # pylint: disable=no-member
        if (result.create_tab_response.status !=
                iterm2.api_pb2.CreateTabResponse.Status.Value("OK")):
            raise iterm2.arrangement.SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    async def async_restore_window_arrangement(self, name: str) -> None:
        """Restore a window arrangement as tabs in this window.

        :param name: The name to restore.

        :throws: :class:`~iterm2.arrangement.SavedArrangementException` if the
            named arrangement does not exist."""
        result = await iterm2.rpc.async_restore_arrangement(
            self.connection, name, self.__window_id)
        # pylint: disable=no-member
        if (result.create_tab_response.status !=
                iterm2.api_pb2.CreateTabResponse.Status.Value("OK")):
            raise iterm2.arrangement.SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    async def async_get_variable(self, name: str) -> typing.Any:
        """
        Fetches a window variable.

        See the Scripting Fundamentals documentation for more information on
        variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        # pylint: disable=no-member
        result = await iterm2.rpc.async_variable(
            self.connection, window_id=self.__window_id, gets=[name])
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))
        return json.loads(result.variable_response.values[0])

    async def async_set_variable(self, name: str, value: typing.Any) -> None:
        """
        Sets a user-defined variable in the window.

        See the Scripting Fundamentals documentation for more information on
        user-defined variables.

        :param name: The variable's name. Must begin with `user.`.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        # pylint: disable=no-member
        result = await iterm2.rpc.async_variable(
            self.connection,
            sets=[(name, json.dumps(value))],
            window_id=self.window_id)
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_set_title(self, title: str):
        """Changes the window's title.

        This is equivalent to editing the window's title with the menu item
        Edit Window Title. The title is an interpolated string. Note that when
        using tmux integration, tab titles correspond to tmux window titles.
        iTerm2's window titles have no equivalent in tmux.

        :param title: The new title. Set it to an empty string to use the
            default value (the current tab's title).

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        invocation = iterm2.util.invocation_string(
            "iterm2.set_title",
            {"title": title})
        await iterm2.rpc.async_invoke_method(
            self.connection, self.window_id, invocation, -1)

    async def async_invoke_function(
            self, invocation: str, timeout: float = -1):
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
        response = await iterm2.rpc.async_invoke_function(
            self.connection,
            invocation,
            window_id=self.window_id,
            timeout=timeout)
        which = response.invoke_function_response.WhichOneof('disposition')
        # pylint: disable=no-member
        if which == 'error':
            if (response.invoke_function_response.error.status ==
                    iterm2.api_pb2.InvokeFunctionResponse.Status.Value(
                        "TIMEOUT")):
                raise iterm2.rpc.RPCException("Timeout")
            raise iterm2.rpc.RPCException("{}: {}".format(
                iterm2.api_pb2.InvokeFunctionResponse.Status.Name(
                    response.invoke_function_response.error.status),
                response.invoke_function_response.error.error_reason))
        return json.loads(
            response.invoke_function_response.success.json_result)
