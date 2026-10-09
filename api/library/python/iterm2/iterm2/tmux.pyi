import abc
from collections.abc import Awaitable, Callable

from .connection import Connection
from .session import Session
from .window import Window

class Delegate(abc.ABC, metaclass=abc.ABCMeta):
    @abc.abstractmethod
    async def tmux_delegate_async_get_window_for_tab_id(
        self, tab_id: str
    ) -> Window | None: ...
    @abc.abstractmethod
    def tmux_delegate_get_session_by_id(self, session_id: str) -> Session | None: ...
    @abc.abstractmethod
    def tmux_delegate_get_connection(self) -> Connection: ...

DELEGATE: Delegate | None
DELEGATE_FACTORY: Callable[[Connection], Awaitable[Delegate]] | None

class TmuxException(Exception): ...

class TmuxConnection:
    def __init__(
        self, connection_id: str, owning_session_id: str, delegate: Delegate
    ) -> None: ...
    @property
    def connection_id(self) -> str: ...
    @property
    def owning_session(self) -> Session | None: ...
    async def async_send_command(self, command: str) -> str: ...
    async def async_set_tmux_window_visible(
        self, tmux_window_id: str, visible: bool
    ) -> None: ...
    async def async_create_window(self) -> Window | None: ...

async def async_get_tmux_connections(
    connection: Connection,
) -> list[TmuxConnection]: ...
async def async_get_tmux_connection_by_connection_id(
    connection: Connection, connection_id: str
) -> TmuxConnection | None: ...
