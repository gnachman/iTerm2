"""Provides interfaces for managing input broadcasting."""
import iterm2.session

class BroadcastDomain:
    """Broadcast domains describe how keyboard input is broadcast.

    A user typing in a session belonging to one broadcast domain will result in
    those keystrokes being sent to all sessions in that domain.

    Broadcast domains are disjoint.
    """
    def __init__(self):
        self.__sessions = []
        self.__unresolved = []

    def add_session(self, session):
        """Adds a session to the broadcast domain.

        :param session: A :class:`iterm2.Session` object."""
        self.__sessions.append(session)

    def add_unresolved(self, resolver):
        self.__unresolved.append(unresolved)

    @property
    def sessions(self):
        """Returns the list of sessions belonging to a broadcast domain.

        :returns: A list of :class:`iterm2.Session` objects."""
        return list(filter(
            lambda x: x is not None,
            self.__sessions + list(map(lambda r: r(), self.__unresolved))))


async def async_set_broadcast_domains(connection, broadcast_domains):
    """Sets the current set of broadcast domains.

    :param broadcast_domains: A list of :class:`iterm2.BroadcastDomain` objects."""
    await iterm2.rpc.async_set_broadcast_domains(connection, list(
        map(lambda d: list(
            map(lambda s: s.session_id,
                d.sessions)),
            broadcast_domains)))

