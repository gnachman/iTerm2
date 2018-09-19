"""Provides access to application-level structures.

This module is the starting point for getting access to windows and other application-global data.
"""

import iterm2.notifications
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.window

import json

async def async_get_app(connection):
    """Returns the app singleton, creating it if needed."""
    if App.instance is None:
        App.instance = await App.async_construct(connection)
    return App.instance

class CreateWindowException(Exception):
    """A problem was encountered while creating a window."""
    pass

class MenuItemException(Exception):
    """A problem was encountered while selecting a menu item."""
    pass

class BroadcastDomain:
    """Broadcast domains describe how keyboard input is broadcast.

    A user typing in a session belonging to one broadcast domain will result in
    those keystrokes being sent to all sessions in that domain.

    Broadcast domains are disjoint.
    """
    def __init__(self, app):
      self.__app = app
      self.__session_ids = []

    def add_session_id(self, session):
      self.__session_ids.append(session)

    @property
    def sessions(self):
      """Returns the list of sessions belonging to a broadcast domain."""
      return list(map(lambda sid: self.__app.get_session_by_id(sid), self.__session_ids))

class App:
    """Represents the application.

    Stores and provides access to app-global state. Holds a collection of
    terminal windows and provides utilities for them.

    This object keeps itself up to date by getting notifications when sessions,
    tabs, or windows change.
    """
    instance = None

    @staticmethod
    async def async_construct(connection):
        """Don't use this directly. Use :func:`async_get_app()`.

        Use this to construct a new hierarchy instead of __init__.
        This exists only because __init__ can't be async.
        """
        response = await iterm2.rpc.async_list_sessions(connection)
        list_sessions_response = response.list_sessions_response
        windows = App._windows_from_list_sessions_response(connection, list_sessions_response)
        buried_sessions = App._buried_sessions_from_list_sessions_response(connection, list_sessions_response)
        app = App(connection, windows, buried_sessions)
        await app._async_listen()
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

    async def async_activate(self, raise_all_windows=True, ignoring_other_apps=False):
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
        windows = []
        for window in response.windows:
            tabs = []
            for tab in window.tabs:
                root = iterm2.session.Splitter.from_node(tab.root, connection)
                if tab.HasField("tmux_window_id"):
                    tmux_window_id = tab.tmux_window_id
                else:
                    tmux_window_id = None
                tabs.append(iterm2.tab.Tab(connection, tab.tab_id, root, tmux_window_id, tab.tmux_connection_id))
            windows.append(iterm2.window.Window(connection, window.window_id, tabs, window.frame, window.number))
        return windows

    @staticmethod
    def _buried_sessions_from_list_sessions_response(connection, response):
        mf = map(lambda summary: iterm2.session.Session(connection, None, summary),
                 response.buried_sessions)
        return list(mf)

    def pretty_str(self):
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

    async def async_refresh_focus(self):
        """Updates state about which objects have focus."""
        focus_info = await iterm2.rpc.async_get_focus_info(self.connection)
        for notif in focus_info.focus_response.notifications:
            await self._async_focus_change(self.connection, notif)

    async def async_refresh_broadcast_domains(self):
        response = await iterm2.rpc.async_get_broadcast_domains(self.connection)
        self._set_broadcast_domains(response.get_broadcast_domains_response.broadcast_domains)

    def get_session_by_id(self, session_id):
        """Finds a session exactly matching the passed-in id.

        :param session_id: The session ID to search for.

        :returns: A :class:`Session` or None.
        """
        return self._search_for_session_id(session_id)

    def get_tab_by_id(self, tab_id):
        """Finds a tab exactly matching the passed-in id.

        :param tab_id: The tab ID to search for.

        :returns: A :class:`Tab` or None.
        """
        return self._search_for_tab_id(tab_id)

    def get_window_by_id(self, window_id):
        """Finds a window exactly matching the passed-in id.

        :param window_id: The window ID to search for.

        :returns: A :class:`Window` or None
        """
        return self._search_for_window_id(window_id)

    def get_window_for_tab(self, tab_id):
        """Finds the window that contains the passed-in tab id.

        :param tab_id: The tab ID to search for.

        :returns: A :class:`Window` or None
        """
        return self._search_for_window_with_tab(tab_id)

    def _search_for_window_with_tab(self, tab_id):
        for window in self.terminal_windows:
            for tab in window.tabs:
                if tab.tab_id == tab_id:
                    return window
        return None

    async def async_refresh(self, _connection=None, _sub_notif=None):
        """Reloads the hierarchy.

        Note that this calls :meth:`async_refresh_focus`.

        You generally don't need to call this explicitly because App keeps its state fresh by
        receiving notifications. One exception is if you need the REPL to pick up changes to the
        state, since it doesn't receive notifications at the Python prompt.
        """
        response = await iterm2.rpc.async_list_sessions(self.connection)
        new_windows = App._windows_from_list_sessions_response(
            self.connection,
            response.list_sessions_response)

        def all_sessions(windows):
            for w in windows:
                for t in w.tabs:
                    for s in t.sessions:
                        yield s

        old_sessions = list(all_sessions(self.terminal_windows))

        windows = []
        new_ids = []
        for new_window in new_windows:
            for new_tab in new_window.tabs:
                for new_session in new_tab.sessions:
                    old = self.get_session_by_id(new_session.session_id)
                    if old is not None:
                        # Upgrade the old session's state
                        old.update_from(new_session)
                        # Replace references to the new session in the new tab with the old session
                        new_tab.update_session(old)
                    old_tab = self.get_tab_by_id(new_tab.tab_id)
                    if old_tab is not None:
                        # Upgrade the old tab's state. This copies the root over. The new tab
                        # has references to old sessions, so it's ok. The only problem is that
                        # splitters are left in the old state.
                        old_tab.update_from(new_tab)
                        # Replace the reference in the new window to the old tab.
                        new_window.update_tab(old_tab)
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
            """Takes a session summary and returns an existing Session if one exists, or else creates a new one."""
            s = find_session(session_summary.unique_identifier, new_sessions)
            if s is None:
                s = find_session(session_summary.unique_identifier, old_sessions)
            if s is None:
                s = iterm2.session.Session(self.connection, None, session_summary)
            return s

        self.__buried_sessions = list(map(get_buried_session, response.list_sessions_response.buried_sessions))
        self.__terminal_windows = windows
        await self.async_refresh_focus()

    async def _async_focus_change(self, _connection, sub_notif):
        """Updates the record of what is in focus."""
        if sub_notif.HasField("application_active"):
            self.app_active = sub_notif.application_active
        elif sub_notif.HasField("window"):
            # Ignore window resigned key notifications because we track the
            # current terminal.
            if sub_notif.window.window_status != iterm2.api_pb2.FocusChangedNotification.Window.WindowStatus.Value("TERMINAL_WINDOW_RESIGNED_KEY"):
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
        self._set_broadcast_domains(sub_notif.broadcast_domains_changed.broadcast_domains)

    def _set_broadcast_domains(self, broadcast_domains):
        self.__broadcast_domains = self.parse_broadcast_domains(broadcast_domains)

    def parse_broadcast_domains(self, list_of_broadcast_domain_protos):
        """Converts a list of broadcast domain protobufs into a list of :class:`BroadcastDomain`s.

        :param list_of_broadcast_domain_protos: A `iterm2.api_pb2.BroadcastDomain` protos.
        :returns: A list of :class:`BroadcastDomain`s.
        """
        domain_list = []
        for broadcast_domain_proto in list_of_broadcast_domain_protos:
            domain = BroadcastDomain(self)
            for sid in broadcast_domain_proto.session_ids:
                domain.add_session_id(sid)
            domain_list.append(domain)
        return domain_list

    @property
    def current_terminal_window(self):
        """Gets the topmost terminal window.

        The current terminal window is the window that receives keyboard input
        when iTerm2 is the active application.

        :returns: :class:`Window` or None
        """
        return self.get_window_by_id(self.current_terminal_window_id)

    @property
    def terminal_windows(self):
        """Returns a list of all terminal windows.

        :returns: A list of :class:`Window`
        """
        return self.__terminal_windows

    @property
    def buried_sessions(self):
        """Returns a list of buried sessions.

        :returns: A list of buried :class:`Session`s.
        """
        return self.__buried_sessions

    @property
    def broadcast_domains(self):
        """Returns the current broadcast domains.

        :returns: A list of :class:`BroadcastDomain`s.
        """
        return self.__broadcast_domains

    def get_tab_and_window_for_session(self, session):
        """Finds the tab and window that own a session.

        :param session: A :class:`Session` object.

        :returns: A tuple of (:class:`Window`, :class:`Tab`).
        """
        for window in self.terminal_windows:
            for tab in window.tabs:
                if session in tab.sessions:
                    return window, tab
        return None, None

    async def _async_listen(self):
        """Subscribe to various notifications that keep this object's state current."""
        connection = self.connection
        self.tokens.append(
            await iterm2.notifications.async_subscribe_to_new_session_notification(
                connection,
                self.async_refresh))
        self.tokens.append(
            await iterm2.notifications.async_subscribe_to_terminate_session_notification(
                connection,
                self.async_refresh))
        self.tokens.append(
            await iterm2.notifications.async_subscribe_to_layout_change_notification(
                connection,
                self.async_refresh))
        self.tokens.append(
            await iterm2.notifications.async_subscribe_to_focus_change_notification(
                connection,
                self._async_focus_change))
        self.tokens.append(
            await iterm2.notifications.async_subscribe_to_broadcast_domains_change_notification(
                connection,
                self._async_broadcast_domains_change))

    async def async_set_variable(self, name, value):
        """
        Sets a user-defined variable in the application.

        See Badges documentation for more information on user-defined variables.

        :param name: The variable's name.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(
            self.connection,
            sets=[(name, json.dumps(value))])
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_get_theme(self):
        """
        Gets attributes the current theme.

        The automatic and minimal themes will always include "dark" or "light".

        On macOS 10.14, the light or dark attribute may be inferred from the system setting.

        :returns: An array of one or more strings from the set: light, dark, automatic, minimal, highContrast.
        """
        s = await self.async_get_variable("effectiveTheme")
        return s.split(" ")

    async def async_get_variable(self, name):
        """
        Fetches an application variable.

        See Badges documentation for more information on variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(self.connection, gets=[name])
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))
        else:
            return json.loads(result.variable_response.values[0])
