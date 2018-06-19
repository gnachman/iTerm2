"""Provides access to application-level structures.

This module is the starting point for getting access to windows and other application-global data.
"""

import iterm2.notifications
import iterm2.profile
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.window

import inspect
import json
import traceback
import websockets

async def async_get_app(connection):
    """Returns the app singleton, creating it if needed."""
    if App.instance is None:
        App.instance = await App.async_construct(connection)
    return App.instance

class CreateWindowException(Exception):
    """A problem was encountered while creating a window."""
    pass

class SavedArrangementException(Exception):
    """A problem was encountered while saving or restoring an arrangement."""
    pass

class MenuItemException(Exception):
    """A problem was encountered while selecting a menu item."""
    pass

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
        return app

    def __init__(self, connection, windows, buried_sessions):
        """Do not call this directly. Use App.construct() instead."""
        self.connection = connection
        self.__terminal_windows = windows
        self.__buried_sessions = buried_sessions
        self.tokens = []

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

    async def async_save_window_arrangement(self, name):
        """Save all windows as a new arrangement.

        Replaces the arrangement with the given name if it already exists.

        :param name: The name of the arrangement.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_save_arrangement(self.connection, name)
        status = result.saved_arrangement_response.status
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    async def async_restore_window_arrangement(self, name):
        """Restore a saved window arrangement.

        :param name: The name of the arrangement to restore.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_restore_arrangement(self.connection, name)
        status = result.saved_arrangement_response.status
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    @staticmethod
    def _windows_from_list_sessions_response(connection, response):
        windows = []
        for window in response.windows:
            tabs = []
            for tab in window.tabs:
                root = iterm2.session.Splitter.from_node(tab.root, connection)
                tabs.append(iterm2.tab.Tab(connection, tab.tab_id, root))
            windows.append(iterm2.window.Window(connection, window.window_id, tabs, window.frame))
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

    async def async_create_window(self, profile=None, command=None, profile_customizations=None):
        """Creates a new window.

        :param profile: The name of the profile to use for the new window.
        :param command: A command to run in lieu of the shell in the new session. Mutually exclusive with profile_customizations.
        :param profile_customizations: LocalWriteOnlyProfile giving changes to make in profile. Mutually exclusive with command.

        :returns: A new :class:`Window`.

        :throws: CreateWindowException if something went wrong.
        """
        if command is not None:
            p = profile.LocalWriteOnlyProfile()
            p.set_use_custom_command(profile.Profile.USE_CUSTOM_COMMAND_ENABLED)
            p.set_command(command)
            custom_dict = p.values
        elif profile_customizations is not None:
            custom_dict = profile_customizations.values
        else:
            custom_dict = None

        result = await iterm2.rpc.async_create_tab(
            self.connection,
            profile=profile,
            window=None,
            profile_customizations=custom_dict)
        ctr = result.create_tab_response
        if ctr.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            session = self.get_session_by_id(ctr.session_id)
            window, _tab = self.get_tab_and_window_for_session(session)
            return window
        else:
            raise CreateWindowException(
                iterm2.api_pb2.CreateTabResponse.Status.Name(
                    result.create_tab_response.status))

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

    async def async_list_profiles(self, guids=None, properties=["Guid", "Name"]):
        """Fetches a list of profiles.

        :param properties: Lists the properties to fetch. Pass None for all.
        :param guids: Lists GUIDs to list. Pass None for all profiles.

        :returns: If properties is a list, returns :class:`PartialProfile` with only the specified properties set. If properties is `None` then returns :class:`Profile`.
        """
        response = await iterm2.rpc.async_list_profiles(self.connection, guids, properties)
        profiles = []
        for responseProfile in response.list_profiles_response.profiles:
            if properties is None:
              profile = iterm2.profile.Profile(None, self.connection, responseProfile.properties)
            else:
              profile = iterm2.profile.PartialProfile(None, self.connection, responseProfile.properties)
            profiles.append(profile)
        return profiles

    async def async_register_rpc_handler(self, name, coro, timeout=None, defaults={}, role=iterm2.notifications.RPC_ROLE_GENERIC, display_name=None):
        """Register a script-defined RPC.

        iTerm2 may be instructed to invoke a script-registered RPC, such as
        through a key binding. Use this method to register one.

        :param name: The RPC name. Combined with its arguments, this must be unique among all registered RPCs. It should consist of letters, numbers, and underscores and must begin with a letter.
        :param coro: An async function. Its arguments are reflected upon to determine the RPC's signature. Only the names of the arguments are used. All arguments should be keyword arguments as any may be omitted at call time.
        :param timeout: How long iTerm2 should wait before giving up on this function's ever returning. `None` means to use the default timeout.
        :param defaults: Gives default values. Names correspond to argument names in `arguments`. Values are in-scope variables at the callsite.
        :param role: Defines the special purpose of this RPC.
        :param display_name: Used by the `RPC_ROLE_SESSION_TITLE` role to give the name of the function to show in preferences.
        The following roles are recognized:

        `RPC_ROLE_GENERIC`: Has no special purpose. Can be invoked in key bindings or triggers.
        `RPC_ROLE_SESSION_TITLE`: Shows as an option to provide session titles in Preferences.
        """
        async def handle_rpc(connection, notif):
            rpc_notif = notif.server_originated_rpc_notification
            params = {}
            ok = False
            try:
                for arg in rpc_notif.rpc.arguments:
                    name = arg.name
                    if arg.HasField("json_value"):
                        # NOTE: This can throw an exception if there are control characters or other nasties.
                        value = json.loads(arg.json_value)
                        params[name] = value
                    else:
                        params[name] = None
                result = await coro(**params)
                ok = True
            except KeyboardInterrupt as e:
                raise e
            except websockets.exceptions.ConnectionClosed as e:
                raise e
            except Exception as e:
                tb = traceback.format_exc()
                exception = { "reason": repr(e), "traceback": tb }
                await iterm2.rpc.async_send_rpc_result(connection, rpc_notif.request_id, True, exception)

            if ok:
                await iterm2.rpc.async_send_rpc_result(connection, rpc_notif.request_id, False, result)

        args = inspect.signature(coro).parameters.keys()
        await iterm2.notifications.async_subscribe_to_server_originated_rpc_notification(self.connection, handle_rpc, name, args, timeout, defaults, role, display_name)

    async def async_select_menu_item(self, identifier):
        """Selects a menu item.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(self.connection, identifier, False)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))

    class MenuItemState:
        """Describes the current state of a menu item.

        There are two properties:

        `checked`: Is there a check mark next to the menu item?
        `enabled`: Is the menu item selectable?
        """
        def __init__(self, checked, enabled):
            self.checked = checked
            self.enabled = enabled

    async def async_get_menu_item_state(self, identifier):
        """Queries a menu item for its state.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`
        :returns: :class:`App.MenuItemState`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(self.connection, identifier, True)
        status = response.menu_item_response.status
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(iterm2.api_pb2.MenuItemResponse.Status.Name(status))
        return iterm2.App.MenuItemState(response.menu_item_response.checked,
                                        response.menu_item_response.enabled)
