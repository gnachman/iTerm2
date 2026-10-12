"""Provides interfaces for managing input broadcasting."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from typing import TYPE_CHECKING

from .api_pb2 import SetBroadcastDomainsResponse
from .rpc import RPCException
from .rpc import async_set_broadcast_domains as _rpc_async_set_broadcast_domains

if TYPE_CHECKING:
    from .connection import Connection
    from .session import Session


class BroadcastDomain:
    """Broadcast domains describe how keyboard input is broadcast.

    A user typing in a session belonging to one broadcast domain will result in
    those keystrokes being sent to all sessions in that domain.

    Broadcast domains are disjoint.

    .. seealso:: Example ":ref:`enable_broadcasting_example`"
    """

    def __init__(self) -> None:
        self.__sessions: list[Session] = []
        self.__unresolved: list[Callable[[], Session | None]] = []

    def add_session(self, session: Session) -> None:
        """Adds a session to the broadcast domain.

        :param session: The session to add."""
        self.__sessions.append(session)

    def add_unresolved(self, unresolved: Callable[[], Session | None]) -> None:
        """Adds an unresolved domain."""
        self.__unresolved.append(unresolved)

    @property
    def sessions(self) -> list[Session]:
        """Returns the list of sessions belonging to a broadcast domain.

        :returns: The sessions belonging to the broadcast domain."""
        resolved = [r() for r in self.__unresolved]
        return [s for s in self.__sessions + resolved if s is not None]


async def async_set_broadcast_domains(
    connection: Connection, broadcast_domains: Iterable[BroadcastDomain]
) -> None:
    """Sets the current set of broadcast domains.

    :param connection: The connection to iTerm2.
    :param broadcast_domains: The new collection of broadcast domains.

    .. seealso:: Example ":ref:`enable_broadcasting_example`"
    """
    response = await _rpc_async_set_broadcast_domains(
        connection,
        [[s.session_id for s in d.sessions] for d in broadcast_domains],
    )
    # pylint: disable=no-member
    if (
        response.set_broadcast_domains_response.status
        != SetBroadcastDomainsResponse.Status.Value("OK")
    ):
        raise RPCException(
            SetBroadcastDomainsResponse.Status.Name(
                response.set_broadcast_domains_response.status
            )
        )
