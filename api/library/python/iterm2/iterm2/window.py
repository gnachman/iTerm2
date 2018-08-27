"""Provides classes that represent iTerm2 windows."""
import json
import iterm2.api_pb2
import iterm2.app
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.util

class CreateTabException(Exception):
    """Something went wrong creating a tab."""
    pass

class SetPropertyException(Exception):
    """Something went wrong setting a property."""
    pass

class GetPropertyException(Exception):
    """Something went wrong fetching a property."""
    pass

class SavedArrangementException(Exception):
    """Something went wrong saving or restoring a saved arrangement."""
    pass

class Window:
    @staticmethod
    async def async_create(connection, profile=None, command=None, profile_customizations=None):
        """Creates a new window.

        :param connection: A :class:`iterm2.Connection`.
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
            connection,
            profile=profile,
            window=None,
            profile_customizations=custom_dict)
        ctr = result.create_tab_response
        if ctr.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            app = await iterm2.app.async_get_app(connection)
            session = app.get_session_by_id(ctr.session_id)
            window, _tab = app.get_tab_and_window_for_session(session)
            return window
        else:
            raise CreateWindowException(
                iterm2.api_pb2.CreateTabResponse.Status.Name(
                    result.create_tab_response.status))

    """Represents an iTerm2 window."""
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

    def pretty_str(self, indent=""):
        """
        :returns: A nicely formatted string describing the window, its tabs, and their sessions.
        """
        session = indent + "Window id=%s frame=%s\n" % (
            self.window_id, iterm2.util.frame_str(self.frame))
        for tab in self.__tabs:
            session += tab.pretty_str(indent=indent + "  ")
        return session

    @property
    def window_id(self):
        """
        :returns: the window's unique identifier.
        """
        return self.__window_id

    @property
    def tabs(self):
        """
        :returns: a list of iterm2.tab.Tab objects.
        """
        return self.__tabs

    async def async_set_tabs(self, tabs):
        """Changes the tabs and their order.

        The provided tabs may belong to any window. They will be moved if needed. Windows entirely denuded of tabs will be closed.

        All provided tabs will be inserted in the given order starting at the first positions. Any tabs already belonging to this window not in the list will remain after the provided tabs.

        :param tabs: a list of :class:`iterm2.Tab` objects
        :raises: RPCException if something goes wrong.
        """
        tab_ids = map(lambda tab: tab.tab_id, tabs)
        result = await iterm2.rpc.async_reorder_tabs(
            self.connection,
            assignments=[(self.window_id, tab_ids)])

    @property
    def current_tab(self):
        """
        :returns: The current iterm2.Tab in this window or None if it could not be determined.
        """
        for tab in self.__tabs:
            if tab.tab_id == self.selected_tab_id:
                return tab
        return None

    async def async_create_tmux_tab(self, tmux_connection):
        """Creates a new tmux tab in this window.

        :param tmux_connection: A :class:`TmuxConnection` that owns the new tab.

        :returns: :class:`Tab`"""
        tmux_window_id = "{}".format(-(self.__number + 1))
        response = await iterm2.rpc.async_rpc_create_tmux_window(
            self.connection,
            tmux_connection.connection_id,
            tmux_window_id)
        if response.tmux_response.status != iterm2.api_pb2.TmuxResponse.Status.Value("OK"):
            raise CreateTabException(
                iterm2.api_pb2.TmuxResponse.Status.Name(response.tmux_response.status))
        tab_id = response.tmux_response.create_window.tab_id
        app = await iterm2.app.async_get_app(self.connection)
        return app.get_tab_by_id(tab_id)

    async def async_create_tab(self, profile=None, command=None, index=None, profile_customizations=None):
        """
        Creates a new tab in this window.

        :param profile: The profile name to use or None for the default profile.
        :param command: The command to run in the new session, or None for the default for the profile. Mutually exclusive with profile_customizations.
        :param index: The index in the window where the new tab should go (0=first position, etc.)
        :param profile_customizations: LocalWriteOnlyProfile giving changes to make in profile. Mutually exclusive with command.

        :returns: :class:`Tab`

        :raises: CreateTabException if something goes wrong.
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
            window=self.__window_id,
            index=index,
            profile_customizations=custom_dict)
        if result.create_tab_response.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            session_id = result.create_tab_response.session_id
            app = await iterm2.app.async_get_app(self.connection)
            session = app.get_session_by_id(session_id)
            _window, tab = app.get_tab_and_window_for_session(session)
            return tab
        else:
            raise CreateTabException(
                iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

    async def async_get_frame(self):
        """
        Gets the window's frame.

        0,0 is the *bottom* right of the main screen.

        :returns: :class:`Frame`

        :raises: :class:`GetPropertyException` if something goes wrong.
        """

        response = await iterm2.rpc.async_get_property(self.connection, "frame", self.__window_id)
        status = response.get_property_response.status
        if status == iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"):
            frame_dict = json.loads(response.get_property_response.json_value)
            frame = iterm2.Frame()
            frame.load_from_dict(frame_dict)
            return frame
        else:
            raise GetPropertyException(response.get_property_response.status)

    async def async_set_frame(self, frame):
        """
        Sets the window's frame.

        :param frame: :class:`Frame`

        :raises: :class:`SetPropertyException` if something goes wrong.
        """
        json_value = json.dumps(frame.dict)
        response = await iterm2.rpc.async_set_property(
            self.connection,
            "frame",
            json_value,
            window_id=self.__window_id)
        status = response.set_property_response.status
        if status != iterm2.api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.get_property_response.status)

    async def async_get_fullscreen(self):
        """
        Checks if the window is full-screen.

        :returns: True (fullscreen) or False (not fullscreen)

        :raises: :class:`GetPropertyException` if something goes wrong.
        """
        response = await iterm2.rpc.async_get_property(self.connection, "fullscreen", self.__window_id)
        status = response.get_property_response.status
        if status == iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"):
            return json.loads(response.get_property_response.json_value)
        else:
            raise GetPropertyException(response.get_property_response.status)


    async def async_set_fullscreen(self, fullscreen):
        """
        Changes the window's full-screen status.

        :param fullscreen: True to make fullscreen, False to make not-fullscreen

        :raises: :class:`SetPropertyException` if something goes wrong.
        """
        json_value = json.dumps(fullscreen)
        response = await iterm2.rpc.async_set_property(
            self.connection,
            "fullscreen",
            json_value,
            window_id=self.__window_id)
        status = response.get_property_response.status
        if status != iterm2.api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise SetPropertyException(response.get_property_response.status)


    async def async_activate(self):
        """
        Gives the window keyboard focus and orders it to the front.
        """
        await iterm2.rpc.async_activate(
            self.connection,
            False,
            False,
            True,
            window_id=self.__window_id)

    async def async_save_window_as_arrangement(self, name):
        """Save the current window as a new arrangement.

        :param name: The name to save as. Will overwrite if one already exists with this name.
        """
        result = await iterm2.rpc.async_save_arrangement(self.connection, name, self.__window_id)
        if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    async def async_restore_window_arrangement(self, name):
        """Restore a window arrangement as tabs in this window.

        :param name: The name to restore.

        :raises: :class:`SavedArrangementException` if the named arrangement does not exist."""
        result = await iterm2.rpc.async_restore_arrangement(self.connection, name, self.__window_id)
        if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))
