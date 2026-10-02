from types import TracebackType

from .connection import Connection

CURRENT_TRANSACTION: Transaction | None

class Transaction:
    connection: Connection
    def __init__(self, connection: Connection) -> None: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...
    @staticmethod
    def current() -> Transaction | None: ...
