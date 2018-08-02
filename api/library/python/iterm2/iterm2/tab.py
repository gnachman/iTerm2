"""Provides a class that represents an iTerm2 tab."""

import iterm2.rpc
import iterm2.api_pb2
import json

class Tab:
    """Represents a tab."""
    def __init__(self, connection, tab_id, root, tmux_window_id=None, tmux_connection_id=None):
        self.connection = connection
        self.__tab_id = tab_id
        self.__root = root
        self.active_session_id = None
        self.__tmux_window_id = tmux_window_id
        self.__tmux_connection_id = tmux_connection_id

    def __repr__(self):
        return "<Tab id=%s sessions=%s>" % (self.__tab_id, self.sessions)

    def update_from(self, other):
        """Copies state from another tab into this one."""
        self.__root = other.root
        self.active_session_id = other.active_session_id

    def update_session(self, session):
        """Replaces references to a session."""
        self.__root.update_session(session)

    @property
    def tmux_connection_id(self):
        return self.__tmux_connection_id

    @property
    def tab_id(self):
        """
        Each tab has a globally unique identifier.

        :returns: The tab's identifier.
        """
        return self.__tab_id

    @property
    def sessions(self):
        """
        A tab contains a list of sessions, which are its split panes.

        :returns: A list of :class:`Session` objects belonging to this tab.
        """
        return self.__root.sessions

    @property
    def root(self):
        """
        A tab's sessions are stored in a tree. This returns the root.

        An interior node of the tree is a Splitter. That corresponds to a
        collection of adjacent sessions with split pane dividers that are all
        either vertical or horizontal.

        Leaf nodes are Sessions.

        :returns: An :class:`Splitter` forming the root of this tab's session tree.
        """
        return self.__root

    @property
    def current_session(self):
        """
        :returns: The active iterm2.Session in this tab or None if it could not be determined.
        """
        for session in self.sessions:
            if session.session_id == self.active_session_id:
                return session
        return None

    def pretty_str(self, indent=""):
        """
        :returns: A human readable description of the tab and its sessions.
        """
        session = indent + "Tab id=%s\n" % self.tab_id
        session += self.__root.pretty_str(indent=indent + "  ")
        return session

    async def async_select(self, order_window_front=True):
        """
        Selects this tab.

        :param order_window_front: Whether the window this session is in should be
          brought to the front and given keyboard focus.
        """
        await iterm2.rpc.async_activate(
            self.connection,
            False,
            True,
            order_window_front,
            tab_id=self.__tab_id)

    async def async_update_layout(self):
        """Adjusts the layout of the sessions in this tab.

        Change the `Session.preferred_size` of any sessions you wish to adjust before calling this.
        """
        response = await iterm2.rpc.async_set_tab_layout(self.connection, self.tab_id, self.__root.to_protobuf())
        status = response.set_tab_layout_response.status
        if status == iterm2.api_pb2.SetTabLayoutResponse.Status.Value("OK"):
            return response.set_tab_layout_response
        else:
            raise iterm2.rpc.RPCException(iterm2.api_pb2.SetTabLayoutResponse.Status.Name(status))

    @property
    def tmux_window_id(self):
        """Returns this tab's tmux window id or None.

        :returns: A tmux window id (a string) or None if this is not a tmux integration window.
        """
        return self.__tmux_window_id

    async def async_set_variable(self, name, value):
        """
        Sets a user-defined variable in the tab.

        See Badges documentation for more information on user-defined variables.

        :param name: The variable's name.
        :param value: The new value to assign.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(
            self.connection,
            sets=[(name, json.dumps(value))],
            tab_id=self.__tab_id)
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))

    async def async_get_variable(self, name):
        """
        Fetches a tab variable.

        See Badges documentation for more information on variables.

        :param name: The variable's name.

        :returns: The variable's value or empty string if it is undefined.

        :throws: :class:`RPCException` if something goes wrong.
        """
        result = await iterm2.rpc.async_variable(self.connection, gets=[name], tab_id=self.__tab_id)
        status = result.variable_response.status
        if status != iterm2.api_pb2.VariableResponse.Status.Value("OK"):
            raise iterm2.rpc.RPCException(iterm2.api_pb2.VariableResponse.Status.Name(status))
        else:
            return json.loads(result.variable_response.values[0])
