"""Provides access to application-level structures.

This module is the starting point for getting access to windows and other
application-global data.
"""
import json
import typing

import iterm2.broadcast
import iterm2.connection
import iterm2.notifications
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.tmux
import iterm2.window


# For backward compatibility. This was moved to the window submodule, and is a
# public API.
CreateWindowException = iterm2.window.CreateWindowException

async def async_get_app(
        connection: iterm2.connection.Connection,
        create_if_needed: bool = True) -> typing.Union[None, 'App']:
    """Returns the app singleton, creating it if needed.

    :param connection: The connection to iTerm2.
    :param create_if_needed: If `True`, create the global :class:`App` instance
      if one does not already exists. If `False`, do not create it.

    :returns: The global :class:`App` instance. If `create_if_needed` is False
      this may return `None` if no such instance exists."""
    if App.instance is None:
        if create_if_needed:
            App.instance = await App.async_construct(connection)
    else:
        await App.instance.async_refresh()
    return App.instance


# See note in tmux.async_get_tmux_connections()
iterm2.tmux.DELEGATE_FACTORY = async_get_app  # type: ignore
iterm2.window.DELEGATE_FACTORY = async_get_app  # type: ignore


# pylint: disable=too-many-public-methods
class App(
        iterm2.session.Session.Delegate,
        iterm2.tab.Tab.Delegate,
        iterm2.tmux.Delegate,
        iterm2.window.Window.Delegate):
    """Represents the application.

    Stores and provides access to app-global state. Holds a collection of
    terminal windows and provides utilities for them.

    This object keeps itself up to date by getting notifications when sessions,
    tabs, or windows change.
    """
    instance: typing.Union[None, 'App'] = None

    @staticmethod
    async def async_construct(
            connection: iterm2.connection.Connection) -> 'App':
        """Don't use this directly. Use :func:`async_get_app()`.

        Use this to construct a new hierarchy instead of __init__.
        This exists only because __init__ can't be async.
        """
        response = await iterm2.rpc.async_list_sessions(connection)
        list_sessions_response = response.list_sessions_response
        windows = App._windows_from_list_sessions_response(
            connection, list_sessions_response)
        buried_sessions = App._buried_sessions_from_list_sessions_response(
            connection, list_sessions_response)
        app = App(connection, windows, buried_sessions)
        iterm2.session.Session.delegate = app
        iterm2.tab.Tab.delegate = app
        iterm2.window.Window.delegate = app
        iterm2.tmux.DELEGATE = app

        # pylint: disable=protected-access
        await app._async_listen()
        # pylint: enable=protected-access
        await app.async_refresh_focus()
        await app.async_refresh_broadcast_domains()
        return app

    def __init__(self, connection, windows, buried_sessions):
        """Do not call this directly. Use App.construct() instead."""
        self.connection = connection
        self.__terminal_windows = windows
        self.__buried_sessions = buried_sessions
        self.tokens = []
        self.__broadcast_domains = []

        # None in these fields means unknown. Notifications will update them.
        self.app_active = None
        self.current_terminal_window_id = None

    async def async_activate(
            self,
            raise_all_windows: bool = True,
            ignoring_other_apps: bool = False) -> None:
        """Activate the app, giving it keyboard focus.

        :param raise_all_windows: Raise all windows if True, or only the key
            window. Defaults to True.
        :param ignoring_other_apps: If True, activate even if the user
            interacts with another app after the call.
        """
        opts = []
        if raise_all_windows:
            opts.append(iterm2.rpc.ACTIVATE_RAISE_ALL_WINDOWS)
        if ignoring_other_apps:
            opts.append(iterm2.rpc.ACTIVATE_IGNORING_OTHER_APPS)
        await iterm2.rpc.async_activate(
            self.connection,
            False,
            False,
            False,
            activate_app_opts=opts)

    @staticmethod
    def _windows_from_list_sessions_response(connection, response):
        return list(
            filter(
                lambda x: x,
                map(lambda window: iterm2.window.Window.create_from_proto(
                    connection, window),
                    response.windows)))

    @staticmethod
    def _buried_sessions_from_list_sessions_response(connection, response):
        """
        Create a list of Session objects representing buried sessions from a
        protobuf.
        """
        sessions = map(
            lambda summary: iterm2.session.Session(
                connection, None, summary),
            response.buried_sessions)
        return list(sessions)

    def pretty_str(self) -> str:
        """Returns the hierarchy as a human-readable string"""
        session = ""
        for window in self.terminal_windows:
            if session:
                session += "\n"
            session += window.pretty_str(indent="")
        return session

    def _search_for_session_id(self, session_id):
        if session_id == "active":
            return iterm2.session.Session.active_proxy(self.connection)
        if session_id == "all":
            return iterm2.session.Session.all_proxy(self.connection)

        for window in self.terminal_windows:
            for tab in window.tabs:
                sessions = tab.sessions
                for session in sessions:
                    if session.session_id == session_id:
                        return session
        return None

    def _search_for_tab_id(self, tab_id):
        for window in self.terminal_windows:
            for tab in window.tabs:
                if tab_id == tab.tab_id:
                    return tab
        return None

    def _search_for_window_id(self, window_id):
        for window in self.terminal_windows:
            if window_id == window.window_id:
                return window
        return None

    async def async_refresh_focus(self) -> None:
        """Updates state about which objects have focus."""
        focus_info = await iterm2.rpc.async_get_focus_info(self.connection)
        for notif in focus_info.focus_response.notifications:
            await self._async_focus_change(self.connection, notif)

    async def async_refresh_broadcast_domains(self) -> None:
        """
        Reload the list of broadcast domains.
        """
        response = await iterm2.rpc.async_get_broadcast_domains(
            self.connection)
        self._set_broadcast_domains(
            response.get_broadcast_domains_response.broadcast_domains)

    def get_session_by_id(
            self,
            session_id: str) -> typing.Union[None, iterm2.session.Session]:
        """Finds a session exactly matching the passed-in id.

        :param session_id: The session ID to search for.

        :returns: A :class:`Session` or `None`.
        """
        assert session_id
        return self._search_for_session_id(session_id)

    def get_tab_by_id(self, tab_id: str) -> typing.Union[iterm2.tab.Tab, None]:
        """Finds a tab exactly matching the passed-in id.

        :param tab_id: The tab ID to search for.

        :returns: A :class:`Tab` or `None`.
        """
        return self._search_for_tab_id(tab_id)

    def get_window_by_id(
            self, window_id: str) -> typing.Union[iterm2.window.Window, None]:
        """Finds a window exactly matching the passed-in id.

        :param window_id: The window ID to search for.

        :returns: A :class:`Window` or `None`.
        """
        return self._search_for_window_id(window_id)

    def get_window_for_tab(
            self, tab_id: str) -> typing.Union[iterm2.window.Window, None]:
        """Finds the window that contains the passed-in tab id.

        :param tab_id: The tab ID to search for.

        :returns: A :class:`Window` or `None`.
        """
        return self._search_for_window_with_tab(tab_id)

    def _search_for_window_with_tab(self, tab_id):
        for window in self.terminal_windows:
            for tab in window.tabs:
                if tab.tab_id == tab_id:
                    return window
        return None

    async def async_refresh(
            self,
            _connection: typing.Optional[iterm2.connection.Connection] = None,
            _sub_notif: typing.Any = None) -> None:
        """Reloads the hierarchy.

        Note that this calls :meth:`async_refresh_focus`.

        Note: Do not use the _connection argument. It is only there to satisfy
        the expected interface for a notification callback. This is often
        called directly with the parameter unset.

        You generally don't need to call this explicitly because App keeps its
        state fresh by receiving notifications. One exception is if you need
        the REPL to pick up changes to the state, since it doesn't receive
        notifications at the Python prompt.
        """
        layout = await iterm2.rpc.async_list_sessions(self.connection)
        return await self._async_handle_layout_change(self.connection, layout)

    # pylint: disable=too-many-locals
    async def _async_handle_layout_change(
            self,
            _connection: typing.Optional[iterm2.connection.Connection],
            layout: typing.Any) -> None:
        """Layout change notification handler. Also called by async_refresh.

        Note: Do not use the connection argument. It is only there to satisfy
        the expected interface for a notification callback. This is often
        called directly with the parameter unset.
        """
        list_sessions_response = layout.list_sessions_response
        new_windows = App._windows_from_list_sessions_response(
            self.connection,
            list_sessions_response)

        def all_sessions(windows):
            for window in windows:
                for tab in window.tabs:
                    for value in tab.sessions:
                        yield value

        old_sessions = list(all_sessions(self.terminal_windows))

        windows = []
        new_ids: typing.List[str] = []
        for new_window in new_windows:
            for new_tab in new_window.tabs:
                for new_session in new_tab.sessions:
                    # Update existing sessions
                    old = self.get_session_by_id(new_session.session_id)
                    if old is not None:
                        # Upgrade the old session's state
                        old.update_from(new_session)
                        # Replace references to the new session in the new tab
                        # with the old session
                        new_tab.update_session(old)
                # Update existing tabs
                old_tab = self.get_tab_by_id(new_tab.tab_id)
                if old_tab is not None:
                    # Upgrade the old tab's state. This copies the root over.
                    # The new tab has references to old sessions, so it's ok.
                    # The only problem is that splitters are left in the old
                    # state.
                    old_tab.update_from(new_tab)
                    # Replace the reference in the new window to the old tab.
                    new_window.update_tab(old_tab)
            # Update existing windows.
            if new_window.window_id not in new_ids:
                new_ids.append(new_window.window_id)
                old_window = self.get_window_by_id(new_window.window_id)
                if old_window is not None:
                    old_window.update_from(new_window)
                    windows.append(old_window)
                else:
                    windows.append(new_window)

        new_sessions = list(all_sessions(self.terminal_windows))

        def find_session(id_wanted, sessions):
            """Finds a session by ID."""
            for session in sessions:
                if session.session_id == id_wanted:
                    return session
            return None

        def get_buried_session(session_summary):
            """
            Takes a session summary and returns an existing Session if one
            exists, or else creates a new one.
            """
            value = find_session(
                session_summary.unique_identifier, new_sessions)
            if value is None:
                value = find_session(
                    session_summary.unique_identifier, old_sessions)
            if value is None:
                value = iterm2.session.Session(
                    self.connection, None, session_summary)
            return value

        self.__buried_sessions = list(
            map(get_buried_session, list_sessions_response.buried_sessions))
        self.__terminal_windows = windows
        await self.async_refresh_focus()
    # pylint: enable=too-many-locals

    async def _async_focus_change(self, _connection, sub_notif):
        """Updates the record of what is in focus."""
        if sub_notif.HasField("application_active"):
            self.app_active = sub_notif.application_active
        elif sub_notif.HasField("window"):
            # Ignore window resigned key notifications because we track the
            # current terminal.
            # pylint: disable=no-member
            if (sub_notif.window.window_status !=
                    iterm2.api_pb2.FocusChangedNotification.Window.
                    WindowStatus.Value(
                        "TERMINAL_WINDOW_RESIGNED_KEY")):
                self.current_terminal_window_id = sub_notif.window.window_id
        elif sub_notif.HasField("selected_tab"):
            window = self.get_window_for_tab(sub_notif.selected_tab)
            if window is None:
                await self.async_refresh()
            else:
                window.selected_tab_id = sub_notif.selected_tab
        elif sub_notif.HasField("session"):
            session = self.get_session_by_id(sub_notif.session)
            window, tab = self.get_tab_and_window_for_session(session)
            if tab is None:
                await self.async_refresh()
            else:
                tab.active_session_id = sub_notif.session

    async def _async_broadcast_domains_change(self, _connection, sub_notif):
        """Updates the current set of broadcast domains."""
        self._set_broadcast_domains(
            sub_notif.broadcast_domains_changed.broadcast_domains)

    def _set_broadcast_domains(self, broadcast_domains):
        self.__broadcast_domains = self.parse_broadcast_domains(
            broadcast_domains)

    def parse_broadcast_domains(
            self,
            list_of_broadcast_domain_protos:
                typing.List[iterm2.api_pb2.BroadcastDomain]) -> typing.List[
                    iterm2.broadcast.BroadcastDomain]:
        """
        Converts a list of broadcast domain protobufs into a list of
        :class:`BroadcastDomain` objects.

        :param list_of_broadcast_domain_protos: A list of `BroadcastDomain`
            protos.
        :returns: A list of :class:`BroadcastDomain` objects.
        """
        domain_list = []

        # Using the loop iterator in a lambda doesn't work because all the
        # lambdas get the same (last) value of sid. Instead, we do this based
        # on https://stackoverflow.com/questions/12423614.
        def session_lookup_callable(sid=None):
            def inner():
                return self.get_session_by_id(sid)
            return inner

        for broadcast_domain_proto in list_of_broadcast_domain_protos:
            domain = iterm2.broadcast.BroadcastDomain()
            for sid in broadcast_domain_proto.session_ids:
                session = self.get_session_by_id(sid)
                if session:
                    domain.add_session(session)
                else:
                    domain.add_unresolved(session_lookup_callable(sid))
            domain_list.append(domain)
        return domain_list

    @property
    def current_window(self) -> typing.Optional[iterm2.window.Window]:
        """Gets the topmost terminal window.

        The current terminal window is the window that receives keyboard input
        when iTerm2 is the active application.

        :returns: A :class:`Window` or `None`.
        """
        return self.get_window_by_id(self.current_terminal_window_id)

    @property
    def current_terminal_window(
            self) -> typing.Union[iterm2.window.Window, None]:
        """Deprecated in favor of current_window."""
        return self.current_window

    @property
    def windows(self) -> typing.List[iterm2.window.Window]:
        """Returns a list of all terminal windows.

        :returns: A list of :class:`Window`
        """
        return self.__terminal_windows

    @property
    def terminal_windows(self) -> typing.List[iterm2.window.Window]:
        """Deprecated in favor of `windows`"""
        return self.windows

    @property
    def buried_sessions(self) -> typing.List[iterm2.session.Session]:
        """Returns a list of buried sessions.

        :returns: A list of buried :class:`Session` objects.
        """
        return self.__buried_sessions

    @property
    def broadcast_domains(
            self) -> typing.List[iterm2.broadcast.BroadcastDomain]:
        """Returns the current broadcast domains.

        .. seealso::
            * Example ":ref:`targeted_input_example`"
            * Example ":ref:`enable_broadcasting_example`"
        """
        return self.__broadcast_domains

    def get_tab_and_window_for_session(
            self,
            session: iterm2.session.Session) -> typing.Union[
                typing.Tuple[None, None],
                typing.Tuple[iterm2.window.Window, iterm2.tab.Tab]]:
        """
        Deprecated because the name is wrong for the order of return
        arguments.
        """
        return self.get_window_and_tab_for_session(session)

    def get_window_and_tab_for_session(
            self,
            session: iterm2.session.Session) -> typing.Union[
                typing.Tuple[None, None],
                typing.Tuple[iterm2.window.Window,
                             iterm2.tab.Tab]]:
        """Finds the tab and window that own a session.

        :param session: The session whose tab and window you wish to find.

        :returns: A tuple of (:class:`Window`, :class:`Tab`), or (`None`,
            `None`) if the session was not found.
        """
        for window in self.terminal_windows:
            for tab in window.tabs:
                if session in tab.sessions:
                    return window, tab
        return None, None

    async def _async_listen(self):
        """
        Subscribe to various notifications that keep this object's state
        current.
        """
        connection = self.connection
        self.tokens.append(
            await (
                iterm2.notifications.
                async_subscribe_to_new_session_notification(
                    connection,
                    self.async_refresh)))
        self.tokens.append(
            await (
                iterm2.notifications.
                async_subscribe_to_terminate_session_notification(
                    connection,
                    self.async_refresh)))
        self.tokens.append(
            await (
                iterm2.notifications.
                async_subscribe_to_layout_change_notification(
                    connection,
                    self._async_handle_layout_change)))
        self.tokens.append(
            await (
                iterm2.notifications.
                async_subscribe_to_focus_change_notification(
                    connection,
                    self._async_focus_change)))
        self.tokens.append(
            await (
                iterm2.notifications.
                async_subscribe_to_broadcast_domains_change_notification(
                    connection,
                    self._async_broadcast_domains_change)))

    async def async_set_variable(self, name: str, value: typing.Any) -> None:
        """
        Sets a user-defined variable in the application.

        See the Scripting Fundamentals documentation for more information on
        user-defined variables.

        :param name: The variable's name. Must begin with `user.`.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(
            self.connection,
            sets=[(name, json.dumps(value))])
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_get_theme(self) -> typing.List[str]:
        """
        Gets attributes the current theme.

        The automatic and minimal themes will always include "dark" or "light".

        On macOS 10.14, the light or dark attribute may be inferred from the
        system setting.

        :returns: A list of one or more strings from the set: light, dark,
            automatic, minimal, highContrast.
        """
        value = await self.async_get_variable("effectiveTheme")
        return value.split(" ")

    async def async_get_variable(self, name: str) -> typing.Any:
        """
        Fetches the value of a variable from the global context.

        See `Scripting Fundamentals
        <https://iterm2.com/documentation-scripting-fundamentals.html>`_ for
        details on variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(
            self.connection, gets=[name])
        status = result.variable_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.VariableResponse.Status.Name(status))
        return json.loads(result.variable_response.values[0])

    # Session.Delegate

    def session_delegate_get_tab(self, session):
        # pylint: disable=unused-variable
        ignore, tab_for_session = self.get_window_and_tab_for_session(
            session)
        return tab_for_session

    def session_delegate_get_window(self, session):
        # pylint: disable=unused-variable
        window_for_session, ignore = self.get_window_and_tab_for_session(
            session)
        return window_for_session

    async def session_delegate_create_session(
            self,
            session_id: str) -> typing.Optional['iterm2.session.Session']:
        await self.async_refresh()
        return self.get_session_by_id(session_id)

    # Tab.Delegate

    def tab_delegate_get_window(self, tab):
        return self.get_window_for_tab(tab.tab_id)

    async def tab_delegate_get_window_by_id(
            self,
            window_id: str) -> typing.Optional['iterm2.window.Window']:
        await self.async_refresh()
        return self.get_window_by_id(window_id)

    # Window Delegate
    async def window_delegate_get_window_with_session_id(
            self, session_id: str):
        await self.async_refresh()
        session = self.get_session_by_id(session_id)
        if session is None:
            return None
        window, _tab = self.get_tab_and_window_for_session(session)
        return window

    async def window_delegate_get_tab_by_id(
            self, tab_id: str) -> typing.Optional[iterm2.tab.Tab]:
        await self.async_refresh()
        return self.get_tab_by_id(tab_id)

    async def window_delegate_get_tab_with_session_id(
            self,
            session_id: str) -> typing.Optional[iterm2.tab.Tab]:
        await self.async_refresh()
        session = self.get_session_by_id(session_id)
        if not session:
            return None
        _window, tab = self.get_tab_and_window_for_session(session)
        return tab

    # tmux.Delegate

    async def tmux_delegate_async_get_window_for_tab_id(
            self, tab_id: str) -> typing.Optional[iterm2.window.Window]:
        await self.async_refresh()
        return self.get_window_for_tab(tab_id)

    def tmux_delegate_get_session_by_id(
            self, session_id: str) -> typing.Optional[iterm2.session.Session]:
        return self.get_session_by_id(session_id)

    def tmux_delegate_get_connection(self) -> iterm2.connection.Connection:
        return self.connection

async def async_get_variable(
        connection: iterm2.connection.Connection, name: str) -> typing.Any:
    """
    Fetches the value of a variable from the global context.

    See `Scripting Fundamentals
    <https://iterm2.com/documentation-scripting-fundamentals.html>`_
    for details on variables.

    :param name: The variable's name.

    :returns: The variable's value or empty string if it is undefined.

    :throws: :class:`RPCException` if something goes wrong.
    """
    result = await iterm2.rpc.async_variable(connection, gets=[name])
    status = result.variable_response.status
    # pylint: disable=no-member
    if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
        raise iterm2.rpc.RPCException(
            iterm2.api_pb2.VariableResponse.Status.Name(status))
    return json.loads(result.variable_response.values[0])


async def async_invoke_function(
        connection: iterm2.connection.Connection,
        invocation: str,
        timeout: float = -1):
    """
    Invoke an RPC. Could be a registered function by this or another script of
    a built-in function.

    This invokes the RPC in the global application context. Note that most
    user-defined RPCs expect to be invoked in the context of a session. Default
    variables will be pulled from that scope. If you call a function from the
    wrong context it may fail because its defaults will not be set properly.

    :param invocation: A function invocation string.
    :param timeout: Max number of secondsto wait. Negative values mean to use
        the system default timeout.

    :returns: The result of the invocation if successful.

    :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
    """
    response = await iterm2.rpc.async_invoke_function(
        connection,
        invocation,
        timeout=timeout)
    which = response.invoke_function_response.WhichOneof('disposition')
    if which == 'error':
        # pylint: disable=no-member
        if (response.invoke_function_response.error.status ==
                iterm2.api_pb2.InvokeFunctionResponse.Status.Value("TIMEOUT")):
            raise iterm2.rpc.RPCException("Timeout")
        raise iterm2.rpc.RPCException("{}: {}".format(
            iterm2.api_pb2.InvokeFunctionResponse.Status.Name(
                response.invoke_function_response.error.status),
            response.invoke_function_response.error.error_reason))
    return json.loads(response.invoke_function_response.success.json_result)
