"""Provides classes for interacting with iTerm2 sessions."""
import asyncio

import iterm2.api_pb2
import iterm2.app
import iterm2.connection
import iterm2.keyboard
import iterm2.notifications
import iterm2.profile
import iterm2.rpc
import iterm2.screen
import iterm2.selection
import iterm2.util

import json
import typing

class SplitPaneException(Exception):
    """Something went wrong when trying to split a pane."""
    pass

class Splitter:
    """A container of split pane sessions where the dividers are all aligned the same way.
    """
    def __init__(self, vertical: bool=False):
        """
        :param vertical: Bool. If true, the divider is vertical, else horizontal.
        """
        self.__vertical = vertical
        # Elements are either Splitter or Session
        self.__children: typing.List[typing.Union['Splitter', 'Session']] = []
        # Elements are Session
        self.__sessions: typing.List['Session'] = []

    @staticmethod
    def from_node(node, connection):
        """Creates a new Splitter from a node.

        :param node: :class:`iterm2.api_pb2.SplitTreeNode`
        :param connection: :class:`~iterm2.connection.Connection`

        :returns: A new Splitter.
        """
        splitter = Splitter(node.vertical)
        for link in node.links:
            if link.HasField("session"):
                session = Session(connection, link)
                splitter.add_child(session)
            else:
                subsplit = Splitter.from_node(link.node, connection)
                splitter.add_child(subsplit)
        return splitter

    @property
    def vertical(self) -> bool:
        """Are the dividers in this splitter vertical?"""
        return self.__vertical

    def add_child(self, child: typing.Union['Splitter', 'Session']):
        """
        Adds one or more new sessions to a splitter.

        child: A Session or a Splitter.
        """
        self.__children.append(child)
        if isinstance(child, Session):
            self.__sessions.append(child)
        else:
            self.__sessions.extend(child.sessions)

    @property
    def children(self) -> typing.List[typing.Union['Splitter', 'Session']]:
        """
        :returns: This splitter's children. A list of :class:`Session` or :class:`Splitter` objects.
        """
        return self.__children

    @property
    def sessions(self) -> typing.List['Session']:
        """
        :returns: All sessions in this splitter and all nested splitters. A list of :class:`Session` objects.
        """
        return self.__sessions

    def pretty_str(self, indent: str="") -> str:
        """
        :returns: A string describing this splitter. Has newlines.
        """
        string_value = indent + "Splitter %s\n" % (
            "|" if self.vertical else "-")
        for child in self.__children:
            string_value += child.pretty_str("  " + indent)
        return string_value

    def update_session(self, session):
        """
        Finds a session with the same ID as session. If it exists, replace the reference with
        session.

        :returns: True if the update occurred.
        """
        i = 0
        for child in self.__children:
            if isinstance(child, Session) and child.session_id == session.session_id:
                self.__children[i] = session

                # Update the entry in self.__sessions
                for j in range(len(self.__sessions)):
                    if self.__sessions[j].session_id == session.session_id:
                        self.__sessions[j] = session
                        break

                return True
            elif isinstance(child, Splitter):
                if child.update_session(session):
                    return True
            i += 1
        return False

    def to_protobuf(self):
        node = iterm2.api_pb2.SplitTreeNode()
        node.vertical = self.vertical
        def make_link(obj):
            link = iterm2.api_pb2.SplitTreeNode.SplitTreeLink()
            if isinstance(obj, Session):
                link.session.CopyFrom(obj.to_session_summary_protobuf())
            else:
                link.node.CopyFrom(obj.to_protobuf())
            return link
        links = list(map(make_link, self.children))
        node.links.extend(links)
        return node

class SessionLineInfo:
    def __init__(self, line_info):
        self.__line_info = line_info

    @property
    def mutable_area_height(self) -> int:
        """Returns the height of the mutable area of the session."""
        return self.__line_info[0]

    @property
    def scrollback_buffer_height(self) -> int:
        """Returns the height of the immutable area of the session."""
        return self.__line_info[1]

    @property
    def overflow(self) -> int:
        """Returns the number of lines lost to overflow. These lines were removed after scrollback history became full."""
        return self.__line_info[2]

    @property
    def first_visible_line_number(self) -> int:
        """Returns the line number of the first line currently displayed onscreen. Changes when the user scrolls."""
        return self.__line_info[3]

class Session:
    """
    Represents an iTerm2 session.
    """

    @staticmethod
    def active_proxy(connection: iterm2.connection.Connection) -> 'Session':
        """
        Use this to register notifications against the currently active session.

        :param connection: The connection to iTerm2.

        :returns: A proxy for the currently active session.
        """
        return ProxySession(connection, "active")

    @staticmethod
    def all_proxy(connection: iterm2.connection.Connection):
        """
        Use this to register notifications against all sessions, including those
        not yet created.

        :param connection: The connection to iTerm2.

        :returns: A proxy for all sessions.
        """
        return ProxySession(connection, "all")

    def __init__(self, connection, link, summary=None):
        """
        Do not call this yourself. Use :class:`~iterm2.app.App` instead.

        :param connection: :class:`Connection`
        :param link: :class:`iterm2.api_pb2.SplitTreeNode.SplitTreeLink`
        :param summary: :class:`iterm2.api_pb2.SessionSummary`
        """
        self.connection = connection

        if link is not None:
            self.__session_id = link.session.unique_identifier
            self.frame = link.session.frame
            self.__grid_size = link.session.grid_size
            self.name = link.session.title
            self.buried = False
        elif summary is not None:
            self.__session_id = summary.unique_identifier
            self.name = summary.title
            self.buried = True
            self.__grid_size = None
            self.frame = None
        self.__preferred_size = self.grid_size

    def __repr__(self):
        return "<Session name=%s id=%s>" % (self.name, self.__session_id)

    def to_session_summary_protobuf(self):
        summary = iterm2.api_pb2.SessionSummary()
        summary.unique_identifier = self.session_id
        summary.grid_size.width = self.preferred_size.width
        summary.grid_size.height = self.preferred_size.height
        return summary

    def update_from(self, session):
        """Replace internal state with that of another session."""
        self.frame = session.frame
        self.__grid_size = session.grid_size
        self.name = session.name

    def pretty_str(self, indent: str="") -> str:
        """
        :returns: A string describing the session.
        """
        return indent + "Session \"%s\" id=%s %s frame=%s\n" % (
            self.name,
            self.__session_id,
            iterm2.util.size_str(self.grid_size),
            iterm2.util.frame_str(self.frame))

    @property
    def preferred_size(self) -> iterm2.util.Size:
        """The size in cells to resize to when `Tab.async_update_layout()` is called."""
        return self.__preferred_size

    @preferred_size.setter
    def preferred_size(self, value: iterm2.util.Size):
        """Sets the size in cells to resize to when `Tab.async_update_layout()` is called."""
        self.__preferred_size = value

    @property
    def session_id(self) -> str:
        """
        :returns: the globally unique identifier for this session.
        """
        return self.__session_id

    async def async_get_screen_contents(self) -> iterm2.screen.ScreenContents:
        """
        Returns the contents of the mutable area of the screen.

        :returns: A :class:`iterm2.screen.ScreenContents`, containing the screen contents.
        """
        result = await iterm2.rpc.async_get_screen_contents(
            self.connection,
            self.session_id)
        if result.get_buffer_response.status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
            return iterm2.screen.ScreenContents(result.get_buffer_response)
        else:
            raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(result.get_buffer_response.status))

    def get_screen_streamer(self, want_contents: bool=True) -> iterm2.screen.ScreenStreamer:
        """
        Provides a nice interface for receiving updates to the screen.

        The screen is the mutable part of a session (its last lines, excluding
        scrollback history).

        :param want_contents: If `True`, the screen contents will be provided. See :class:`~iterm2.screen.ScreenStreamer` for details.

        :returns: A new screen streamer, suitable for monitoring the contents of this session.

        :Example:

          async with session.get_screen_streamer() as streamer:
            while condition():
              contents = await streamer.async_get()
              do_something(contents)
        """
        return iterm2.screen.ScreenStreamer(self.connection, self.__session_id, want_contents=want_contents)

    async def async_send_text(self, text: str, suppress_broadcast: bool=False) -> None:
        """
        Send text as though the user had typed it.

        :param text: The text to send.
        :param suppress_broadcast: If `True`, text goes only to the specified session even if broadcasting is on.

        .. seealso::
            * Example ":ref:`broadcast_example`"
            * Example ":ref:`targeted_input_example`"
        """
        await iterm2.rpc.async_send_text(self.connection, self.__session_id, text, suppress_broadcast)

    async def async_split_pane(
            self,
            vertical: bool=False,
            before: bool=False,
            profile: typing.Union[None, str]=None,
            profile_customizations: typing.Union[None, iterm2.profile.LocalWriteOnlyProfile]=None) -> 'Session':
        """
        Splits the pane, creating a new session.

        :param vertical: If `True`, the divider is vertical, else horizontal.
        :param before: If `True`, the new session will be to the left of or above the session being split. Otherwise, it will be to the right of or below it.
        :param profile: The profile name to use. `None` for the default profile.
        :param profile_customizations: Changes to the profile that should affect only this session, or `None` to make no changes.

        :returns: A newly created Session.

        :throws: :class:`SplitPaneException` if something goes wrong.

        .. seealso:: Example ":ref:`broadcast_example`"
        """
        if profile_customizations is None:
            custom_dict = None
        else:
            custom_dict = profile_customizations.values

        result = await iterm2.rpc.async_split_pane(
            self.connection,
            self.__session_id,
            vertical,
            before,
            profile,
            profile_customizations=custom_dict)
        if result.split_pane_response.status == iterm2.api_pb2.SplitPaneResponse.Status.Value("OK"):
            new_session_id = result.split_pane_response.session_id[0]
            app = await iterm2.app.async_get_app(self.connection)
            assert(app)
            await app.async_refresh()
            session = app.get_session_by_id(new_session_id)
            if session:
                return session
            raise SplitPaneException("No such session {}".format(new_session_id))
        else:
            raise SplitPaneException(
                iterm2.api_pb2.SplitPaneResponse.Status.Name(result.split_pane_response.status))

    async def async_set_profile_properties(self, write_only_profile: iterm2.profile.LocalWriteOnlyProfile) -> None:
        """
        Sets the value of properties in this session.

        When you use this function the underlying profile is not modified. The session will keep a copy of its profile with these modifications.

        :param key: The name of the property
        :param write_only_profile: A write-only profile that has the desired changes.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso::
          * Example ":ref:`copycolor_example`"
          * Example ":ref:`settabcolor_example`"
          * Example ":ref:`increase_font_size_example`"
        """
        for key, json_value in write_only_profile.values.items():
            response = await iterm2.rpc.async_set_profile_property_json(
                self.connection,
                self.session_id,
                key,
                json_value)
            status = response.set_profile_property_response.status
            if status != iterm2.api_pb2.SetProfilePropertyResponse.Status.Value("OK"):
                raise iterm2.rpc.RPCException(iterm2.api_pb2.SetProfilePropertyResponse.Status.Name(status))

    async def async_get_profile(self) -> iterm2.profile.Profile:
        """
        Fetches the profile of this session

        :returns: The profile for this session, including any session-local changes not in the underlying profile.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso::
            * Example ":ref:`blending_example`"
            * Example ":ref:`colorhost_example`"
            * Example ":ref:`current_preset_example`"
            * Example ":ref:`random_color_example`"
        """
        response = await iterm2.rpc.async_get_profile(self.connection, self.__session_id)
        status = response.get_profile_property_response.status
        if status == iterm2.api_pb2.GetProfilePropertyResponse.Status.Value("OK"):
            return iterm2.profile.Profile(
                self.__session_id,
                self.connection,
                response.get_profile_property_response.properties)
        else:
            raise iterm2.rpc.RPCException(
                iterm2.api_pb2.GetProfilePropertyResponse.Status.Name(status))

    async def async_inject(self, data: bytes) -> None:
        """
        Injects data as though it were program output.

        :param data: A byte array to inject.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`cls_example`"
        """
        response = await iterm2.rpc.async_inject(self.connection, data, [self.__session_id])
        status = response.inject_response.status[0]
        if status != iterm2.api_pb2.InjectResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.InjectResponse.Status.Name(status))

    async def async_activate(self, select_tab: bool=True, order_window_front: bool=True) -> None:
        """
        Makes the session the active session in its tab.

        :param select_tab: Whether the tab this session is in should be selected.
        :param order_window_front: Whether the window this session is in should be brought to the front and given keyboard focus.

        .. seealso:: Example ":ref:`broadcast_example`"
        """
        await iterm2.rpc.async_activate(
            self.connection,
            True,
            select_tab,
            order_window_front,
            session_id=self.__session_id)

    async def async_set_variable(self, name: str, value: typing.Any):
        """
        Sets a user-defined variable in the session.

        See Badges documentation for more information on user-defined variables.

        :param name: The variable's name.
        :param value: The new value to assign.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`escindicator_example`"
        """
        result = await iterm2.rpc.async_variable(
            self.connection,
            self.__session_id,
            [(name, json.dumps(value))],
            [])
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_get_variable(self, name: str) -> typing.Any:
        """
        Fetches a session variable.

        See Badges documentation for more information on variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`colorhost_example`"
        """
        result = await iterm2.rpc.async_variable(self.connection, self.__session_id, [], [name])
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))
        else:
            return json.loads(result.variable_response.values[0])

    async def async_restart(self, only_if_exited: bool=False) -> None:
        """
        Restarts a session.

        :param only_if_exited: When `True`, this will raise an exception if the session is still running. When `False`, a running session will be killed and restarted.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_restart_session(self.connection, self.__session_id, only_if_exited)
        status = result.restart_session_response.status
        if status != iterm2.api_pb2.RestartSessionResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.RestartSessionResponse.Status.Name(status))

    async def async_close(self, force: bool=False) -> None:
        """
        Closes the session.

        :param force: If `True`, the user will not be prompted for a confirmation.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_close(self.connection, sessions=[self.__session_id], force=force)
        status = result.close_response.statuses[0]
        if status != iterm2.api_pb2.CloseResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.CloseResponse.Status.Name(status))

    async def async_set_grid_size(self, size: iterm2.util.Size) -> None:
        """Sets the visible size of a session.

        Note: This is meant for tabs that contain a single pane. If split panes are present, use :func:`~iterm2.tab.Tab.async_update_layout` instead.

        :param size: The new size for the session, in cells.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        Note: This will fail on fullscreen windows."""
        await self._async_set_property("grid_size", size.json)

    @property
    def grid_size(self) -> iterm2.util.Size:
        """Returns the size of the visible part of the session in cells.

        :returns: The size of the visible part of the session in cells.
        """
        return self.__grid_size

    async def async_set_buried(self, buried: bool) -> None:
        """Buries or disinters a session.

        :param buried: If `True`, bury the session. If `False`, disinter it.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        await self._async_set_property("buried", json.dumps(buried))


    async def _async_set_property(self, key, json_value):
        """Sets a property on this session.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        response = await iterm2.rpc.async_set_property(self.connection, key, json_value, session_id=self.session_id)
        status = response.set_property_response.status
        if status != iterm2.api_pb2.SetPropertyResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.SetPropertyResponse.Status.Name(status))
        return response

    async def async_get_selection(self) -> iterm2.selection.Selection:
        """
        :returns: The selected regions of this session. The selection will be empty if there is no selected text.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`georges_title_example`"
        """
        response = await iterm2.rpc.async_get_selection(self.connection, self.session_id)
        status = response.selection_response.status
        if status != iterm2.api_pb2.SelectionResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.SelectionResponse.Status.Name(status))
        subs = []
        for subProto in response.selection_response.get_selection_response.selection.sub_selections:
            start = iterm2.util.Point(
                    subProto.windowed_coord_range.coord_range.start.x,
                    subProto.windowed_coord_range.coord_range.start.y)
            end = iterm2.util.Point(
                    subProto.windowed_coord_range.coord_range.end.x,
                    subProto.windowed_coord_range.coord_range.end.y)
            coordRange = iterm2.util.CoordRange(start, end)
            columnRange = iterm2.util.Range(
                    subProto.windowed_coord_range.columns.location,
                    subProto.windowed_coord_range.columns.length)
            windowedCoordRange = iterm2.util.WindowedCoordRange(coordRange, columnRange)

            sub = iterm2.SubSelection(
                    windowedCoordRange,
                    iterm2.selection.SelectionMode.fromProtoValue(
                        subProto.selection_mode),
                    subProto.connected)
            subs.append(sub)
        return iterm2.Selection(subs)

    async def async_get_selection_text(self, selection: iterm2.selection.Selection) -> str:
        """Fetches the text within a selection region.

        :param selection: A :class:`~iterm2.selection.Selection` defining a region in the session.

        .. seealso::
            * :func:`async_get_selection`.
            * Example ":ref:`georges_title_example`"

        :returns: A string with the selection's contents. Discontiguous selections are combined with newlines."""
        return await selection.async_get_string(
                self.connection,
                self.session_id,
                self.grid_size.width)

    async def async_set_selection(self, selection: iterm2.selection.Selection) -> None:
        """
        :param selection: The regions of text to select.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.

        .. seealso:: Example ":ref:`zoom_on_screen_example`"
        """
        response = await iterm2.rpc.async_set_selection(self.connection, self.session_id, selection)
        status = response.selection_response.status
        if status != iterm2.api_pb2.SelectionResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.SelectionResponse.Status.Name(status))

    async def async_get_line_info(self) -> SessionLineInfo:
        """
        Fetches the number of lines that are visible, in history, and that have been removed after history became full.

        :returns: Information about the session's wrapped lines of text.

        .. seealso:: Example ":ref:`zoom_on_screen_example`"
        """
        response = await iterm2.rpc.async_get_property(self.connection, "number_of_lines", session_id=self.session_id)
        status = response.get_property_response.status
        if status != iterm2.api_pb2.GetPropertyResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPropertyResponse.Status.Name(status))
        dict = json.loads(response.get_property_response.json_value)
        t = (dict["grid"], dict["history"], dict["overflow"], dict["first_visible"] )
        return SessionLineInfo(t)

    async def async_invoke_function(self, invocation: str, timeout: float=-1):
        """
        Invoke an RPC. Could be a function registered by this or another script, or a built-in function.

        This invokes the RPC in the context of this session. Most user-defined RPCs are invoked in a session context (for example, invocations attached to triggers or key bindings). Default variables will be pulled from that scope. If you call a function from the wrong context it may fail because its defaults will not be set properly.

        :param invocation: A function invocation string.
        :param timeout: Max number of secondsto wait. Negative values mean to use the system default timeout.

        :returns: The result of the invocation if successful.

        :throws: :class:`~iterm2.rpc.RPCException` if something goes wrong.
        """
        response = await iterm2.rpc.async_invoke_function(
                self.connection,
                invocation,
                session_id=self.session_id,
                timeout=timeout)
        which = response.invoke_function_response.WhichOneof('disposition')
        if which == 'error':
            if response.invoke_function_response.error.status == iterm2.api_pb2.InvokeFunctionResponse.Status.Value("TIMEOUT"):
                raise iterm2.rpc.RPCException("Timeout")
            else:
                raise iterm2.rpc.RPCException("{}: {}".format(
                    iterm2.api_pb2.InvokeFunctionResponse.Status.Name(
                        response.invoke_function_response.error.status),
                    response.invoke_function_response.error.error_reason))
        return json.loads(response.invoke_function_response.success.json_result)


class InvalidSessionId(Exception):
    """The specified session ID is not allowed in this method."""
    pass

class ProxySession(Session):
    """A proxy for a Session.

    This is used when you specify an abstract session ID like "all" or "active".
    Since the session or set of sessions that refers to is ever-changing, this
    proxy stands in for the real thing. It may limit functionality since it
    doesn't make sense to, for example, get the screen contents of "all"
    sessions.
    """
    def __init__(self, connection, session_id):
        super().__init__(connection, session_id)
        self.__session_id = session_id

    def __repr__(self):
        return "<ProxySession %s>" % self.__session_id

    def pretty_str(self, indent=""):
        return indent + "ProxySession %s" % self.__session_id
