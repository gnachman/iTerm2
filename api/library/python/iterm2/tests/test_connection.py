"""Tests for iterm2.connection."""

import asyncio

from websockets.datastructures import Headers
from websockets.legacy.exceptions import InvalidStatusCode

from iterm2.connection import Connection


def test_create_reauthenticates_after_a_401(monkeypatch):
    """A stale cookie gets a 401 from the legacy client, which forces a fresh one."""
    attempts = []
    authentications = []

    async def connect():
        attempts.append(len(attempts))
        if len(attempts) == 1:
            raise InvalidStatusCode(401, Headers())
        return "websocket"

    async def dispatch_forever(self, connection, loop):
        pass

    monkeypatch.setattr(Connection, "_get_connect_coro", lambda self: connect())
    monkeypatch.setattr(Connection, "_async_dispatch_forever", dispatch_forever)
    monkeypatch.setattr(Connection, "_remove_auth", lambda self: None)

    def authenticate(self, force):
        authentications.append(force)
        return force

    monkeypatch.setattr(Connection, "authenticate", authenticate)

    connection = asyncio.run(Connection.async_create())

    assert connection.websocket == "websocket"
    assert len(attempts) == 2
    assert authentications == [False, True]
