"""Provides interfaces for managing input broadcasting."""
import iterm2.connection
import iterm2.session
import typing

class BroadcastDomain:
    """Broadcast domains describe how keyboard input is broadcast.

    A user typing in a session belonging to one broadcast domain will result in
    those keystrokes being sent to all sessions in that domain.

    Broadcast domains are disjoint.

    .. seealso:: Example ":ref:`enable_broadcasting_example`"
    """
    def __init__(self):
        self.__sessions = []
        self.__unresolved = []

    def add_session(self, session: iterm2.session.Session):
        """Adds a session to the broadcast domain.

        :param session: The session to add."""
        self.__sessions.append(session)

    def add_unresolved(self, unresolved):
        self.__unresolved.append(unresolved)

    @property
    def sessions(self) -> typing.List[iterm2.session.Session]:
        """Returns the list of sessions belonging to a broadcast domain.

        :returns: The sessions belonging to the broadcast domain."""
        return list(filter(
            lambda x: x is not None,
            self.__sessions + list(map(lambda r: r(), self.__unresolved))))


async def async_set_broadcast_domains(
    connection: iterm2.connection.Connection,
    broadcast_domains: typing.List[BroadcastDomain]):
    """Sets the current set of broadcast domains.

    :param connection: The connection to iTerm2.
    :param broadcast_domains: The new collection of broadcast domains.

    .. seealso:: Example ":ref:`enable_broadcasting_example`"
    """
    await iterm2.rpc.async_set_broadcast_domains(connection, list(
        map(lambda d: list(
            map(lambda s: s.session_id,
                d.sessions)),
            broadcast_domains)))

