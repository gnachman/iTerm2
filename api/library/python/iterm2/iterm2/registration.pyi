from collections.abc import Awaitable, Callable, Coroutine
from typing import Any, Protocol, TypeVar

from typing_extensions import ParamSpec, TypeAlias

from . import api_pb2
from .connection import Connection
from .notifications import NotificationToken
from .statusbar import StatusBarComponent

_P = ParamSpec("_P")
_R = TypeVar("_R")
_R_co = TypeVar("_R_co", covariant=True)

async def generic_handle_rpc(
    coro: Callable[..., Awaitable[Any]],
    connection: Connection,
    notif: api_pb2.Notification,
) -> None: ...

class Reference:
    name: str
    def __init__(self, name: str) -> None: ...

class _RegisteredFunction(Protocol[_P, _R_co]):
    rpc_token: NotificationToken
    rpc_connection: Connection
    def __call__(self, *args: _P.args, **kwargs: _P.kwargs) -> Coroutine[Any, Any, _R_co]: ...

class _RPCFunction(_RegisteredFunction[_P, _R_co], Protocol[_P, _R_co]):
    async def async_register(
        self, connection: Connection, timeout: float | None = None
    ) -> None: ...

class _ContextMenuProviderRPCFunction(_RegisteredFunction[_P, _R_co], Protocol[_P, _R_co]):
    async def async_register(
        self,
        connection: Connection,
        display_name: str,
        unique_identifier: str,
        timeout: float | None = None,
    ) -> None: ...

class _TitleProviderRPCFunction(_RegisteredFunction[_P, _R_co], Protocol[_P, _R_co]):
    async def async_register(
        self,
        connection: Connection,
        display_name: str,
        unique_identifier: str,
        timeout: float | None = None,
    ) -> None: ...

class _StatusBarRPCFunction(_RegisteredFunction[_P, _R_co], Protocol[_P, _R_co]):
    async def async_register(
        self,
        connection: Connection,
        component: StatusBarComponent,
        timeout: float | None = None,
    ) -> None: ...

StatusBarRPCFunction: TypeAlias = _StatusBarRPCFunction[_P, _R]

def RPC(func: Callable[_P, Coroutine[Any, Any, _R]]) -> _RPCFunction[_P, _R]: ...
def ContextMenuProviderRPC(
    func: Callable[_P, Coroutine[Any, Any, _R]],
) -> _ContextMenuProviderRPCFunction[_P, _R]: ...
def TitleProviderRPC(
    func: Callable[_P, Coroutine[Any, Any, _R]],
) -> _TitleProviderRPCFunction[_P, _R]: ...
def StatusBarRPC(
    func: Callable[_P, Coroutine[Any, Any, _R]],
) -> _StatusBarRPCFunction[_P, _R]: ...
