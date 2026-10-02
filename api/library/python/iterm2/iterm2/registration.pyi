from collections.abc import Awaitable, Callable, Coroutine
from typing import Any, Protocol

from . import api_pb2
from .connection import Connection
from .notifications import NotificationToken
from .statusbar import StatusBarComponent

async def generic_handle_rpc(
    coro: Callable[..., Awaitable[Any]],
    connection: Connection,
    notif: api_pb2.Notification,
) -> None: ...

class Reference:
    name: str
    def __init__(self, name: str) -> None: ...

class _RegisteredFunction[**P, R](Protocol):
    rpc_token: NotificationToken
    rpc_connection: Connection
    def __call__(self, *args: P.args, **kwargs: P.kwargs) -> Coroutine[Any, Any, R]: ...

class _RPCFunction[**P, R](_RegisteredFunction[P, R], Protocol):
    async def async_register(
        self, connection: Connection, timeout: float | None = None
    ) -> None: ...

class _ContextMenuProviderRPCFunction[**P, R](_RegisteredFunction[P, R], Protocol):
    async def async_register(
        self,
        connection: Connection,
        display_name: str,
        unique_identifier: str,
        timeout: float | None = None,
    ) -> None: ...

class _TitleProviderRPCFunction[**P, R](_RegisteredFunction[P, R], Protocol):
    async def async_register(
        self,
        connection: Connection,
        display_name: str,
        unique_identifier: str,
        timeout: float | None = None,
    ) -> None: ...

class _StatusBarRPCFunction[**P, R](_RegisteredFunction[P, R], Protocol):
    async def async_register(
        self,
        connection: Connection,
        component: StatusBarComponent,
        timeout: float | None = None,
    ) -> None: ...

StatusBarRPCFunction = _StatusBarRPCFunction

def RPC[**P, R](func: Callable[P, Coroutine[Any, Any, R]]) -> _RPCFunction[P, R]: ...
def ContextMenuProviderRPC[**P, R](
    func: Callable[P, Coroutine[Any, Any, R]],
) -> _ContextMenuProviderRPCFunction[P, R]: ...
def TitleProviderRPC[**P, R](
    func: Callable[P, Coroutine[Any, Any, R]],
) -> _TitleProviderRPCFunction[P, R]: ...
def StatusBarRPC[**P, R](
    func: Callable[P, Coroutine[Any, Any, R]],
) -> _StatusBarRPCFunction[P, R]: ...
