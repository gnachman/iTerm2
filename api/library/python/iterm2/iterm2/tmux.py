"""Represents tmux integration objects."""
import iterm2.app
import iterm2.rpc

class TmuxException(Exception):
    """A problem was encountered in a Tmux request."""
    pass

class TmuxConnection:
    def __init__(self, connection_id, owning_session_id, app):
        self.__connection_id = connection_id
        self.__owning_session_id = owning_session_id
        self.__app = app

    @property
    def connection_id(self):
        """Returns the unique identifier of the connection.

        :returns: A connection ID (a string), which is also a human-readable description of the connection.
        """
        return self.__connection_id

    @property
    def owning_session(self):
        """Returns the "gateway" session.

        :returns: The :class:`Session` where `tmux -CC` was run, or None if it cannot be found."""
        return self.__app.get_session_by_id(self.__owning_session_id)

    async def async_send_command(self, command):
        """Sends a command to the tmux server.

        :param command: The command to send to tmux (e.g., "list-sessions")

        :returns: The command's output as a string.

        :throws TmuxException: If the command fails for any reason or the RPC fails such as from an invalid ID.
        """
        response = await iterm2.rpc.async_rpc_send_tmux_command(self.__app.connection,
                                                                self.__connection_id,
                                                                command)
        if response.tmux_response.status == iterm2.api_pb2.TmuxResponse.Status.Value("OK"):
            if response.tmux_response.send_command.HasField("output"):
                return response.tmux_response.send_command.output
            else:
                raise TmuxException("Tmux reported an error")
        else:
            raise TmuxException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))

    async def async_set_tmux_window_visible(self, tmux_window_id, visible):
        """Hides or shows a tmux window.

        Tmux windows are represented as tabs in iTerm2. You can get a
        tmux_window_id from :meth:`iterm2.Tab.tmux_window_id`. If this tab is
        attached to a tmux session, then it may be hidden. Use
        :meth:`iterm2.tmux.async_open_window` to make it visible again.

        :param tmux_window_id: The window to show or hide.
        :param visible: `True` to show a window, `False` to hide a window.
        """
        response = await iterm2.rpc.async_rpc_set_tmux_window_visible(self.__app.connection,
                                                                      self.__connection_id,
                                                                      tmux_window_id,
                                                                      visible)
        if response.tmux_response.status != iterm2.api_pb2.TmuxResponse.Status.Value("OK"):
            raise TmuxException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))

    async def async_create_window(self):
        """Creates a new tmux window.

        :returns: A new :class:`Window`.
        """
        response = await iterm2.rpc.async_rpc_create_tmux_window(self.__app.connection,
                                                                 self.__connection_id)
        if response.tmux_response.status != iterm2.api_pb2.TmuxResponse.Status.Value("OK"):
            raise TmuxException(
                iterm2.api_pb2.TmuxResponse.Status.Name(
                    response.tmux_response.status))
        tab_id = response.tmux_response.create_window.tab_id
        app = self.__app
        return app.get_window_for_tab(tab_id)


async def async_get_tmux_connections(connection):
    """Fetches a list of tmux connections.

    :param connection: An existing :class:`iterm2.Connection`.
    :returns: A list of :class:`TmuxConnection` objects.
    """
    response = await iterm2.rpc.async_rpc_list_tmux_connections(connection)
    app = await iterm2.app.async_get_app(connection)
    if response.tmux_response.status == iterm2.api_pb2.TmuxResponse.Status.Value("OK"):
        def make_connection(proto):
            return TmuxConnection(proto.connection_id,
                                  proto.owning_session_id,
                                  app)
        return list(map(make_connection,
                        response.tmux_response.list_connections.connections))
    else:
        raise TmuxException(
            iterm2.api_pb2.TmuxResponse.Status.Name(
                response.tmux_response.status))

async def async_get_tmux_connection_by_connection_id(connection, connection_id):
    """Find a tmux connection by its ID.

    :param connection: An existing :class:`iterm2.Connection`.
    :param connection_id: A connection ID for a :class:`TmuxConnection`.

    :returns: Either a :class:`TmuxConnection` or `None`.
    """
    connections = await async_get_tmux_connections(connection)
    for tc in connections:
        if tc.connection_id == connection_id:
            return tc
    return None
