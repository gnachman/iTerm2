"""Tests for the RPC decorators in iterm2.registration."""
import asyncio

import pytest

import iterm2
from iterm2 import registration


@pytest.mark.parametrize(
    "decorator",
    [
        registration.RPC,
        registration.ContextMenuProviderRPC,
        registration.TitleProviderRPC,
        registration.StatusBarRPC,
    ],
)
def test_decorators_attach_async_register_to_the_function(decorator):
    """Each decorator returns the function itself with async_register added."""

    async def handler():
        pass

    decorated = decorator(handler)

    assert decorated is handler
    assert callable(decorated.async_register)


def test_rpc_async_register_subscribes_and_records_the_registration(monkeypatch):
    """async_register subscribes with the function's signature and stores the
    resulting token and connection on the function."""
    calls = []

    async def subscribe(
        connection, callback, name, arguments, timeout, defaults, role
    ):
        calls.append((connection, name, list(arguments), timeout, defaults, role))
        return "token"

    monkeypatch.setattr(
        registration,
        "async_subscribe_to_server_originated_rpc_notification",
        subscribe,
    )

    @registration.RPC
    async def handler(count, session_id=iterm2.Reference("id")):
        pass

    connection = object()
    asyncio.run(handler.async_register(connection, timeout=3))

    assert calls == [
        (
            connection,
            "handler",
            ["count", "session_id"],
            3,
            {"session_id": "id"},
            registration.RPC_ROLE_GENERIC,
        )
    ]
    assert handler.rpc_token == "token"
    assert handler.rpc_connection is connection
