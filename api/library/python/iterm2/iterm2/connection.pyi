import types
from asyncio import AbstractEventLoop, Future
from collections.abc import Callable, Coroutine
from typing import Any, TypeAlias

from websockets.legacy.client import WebSocketClientProtocol

from . import api_pb2
from ._version import __version__ as __version__

gDisconnectCallbacks: list[Callable[[], None]]
websockets_client: types.ModuleType

ConnectionCoroutine: TypeAlias = Callable[[Connection], Coroutine[Any, Any, None]]
ConnectionHelper: TypeAlias = Callable[
    [Connection, api_pb2.ServerOriginatedMessage], Coroutine[Any, Any, Any]
]

class Connection:
    helpers: list[ConnectionHelper]
    @staticmethod
    def register_helper(helper: ConnectionHelper) -> None: ...
    @staticmethod
    async def async_create() -> Connection: ...
    websocket: WebSocketClientProtocol | None
    loop: AbstractEventLoop | None
    def __init__(self) -> None: ...
    def run_until_complete[T](
        self,
        coro: Callable[[Connection], Coroutine[Any, Any, T]],
        retry: bool,
        debug: bool = False,
    ) -> T: ...
    def run_forever(
        self,
        coro: Callable[[Connection], Coroutine[Any, Any, Any]],
        retry: bool,
        debug: bool = False,
    ) -> None: ...
    def set_message_in_future[T](
        self, loop: AbstractEventLoop, message: T, future: Future[T]
    ) -> None: ...
    def run[T](
        self,
        forever: bool,
        coro: Callable[[Connection], Coroutine[Any, Any, T]],
        retry: bool,
        debug: bool = False,
    ) -> T: ...
    async def async_send_message(
        self, message: api_pb2.ClientOriginatedMessage
    ) -> None: ...
    async def async_dispatch_until_id(
        self, reqid: int
    ) -> api_pb2.ServerOriginatedMessage: ...
    @property
    def iterm2_protocol_version(self) -> tuple[int, int]: ...
    def authenticate(self, force: bool) -> bool: ...
    async def async_connect[T](
        self, coro: Callable[[Connection], Coroutine[Any, Any, T]], retry: bool = False
    ) -> T: ...

def run_until_complete(
    coro: ConnectionCoroutine,
    retry: bool = False,
    debug: bool = False,
) -> None: ...
def run_forever(
    coro: ConnectionCoroutine,
    retry: bool = False,
    debug: bool = False,
) -> None: ...
def add_disconnect_callback(callback: Callable[[], None]) -> None: ...
