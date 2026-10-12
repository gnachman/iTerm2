"""Provides a class to facilitate atomic transactions."""

from __future__ import annotations

from typing import TYPE_CHECKING

from .rpc import async_end_transaction, async_start_transaction

if TYPE_CHECKING:
    import types

    from .connection import Connection

gCURRENT_TRANSACTION: Transaction | None = None


class Transaction:
    """An asyncio context manager for transactions.

    A transaction is a sequence of API calls that occur without anything else
    happening in between. If you're worried about state mutating between
    reading the screen contents and then sending text, for example, do it in a
    transaction and you'll know the state of the terminal will remain unchanged
    during it.

    Some APIs are noted as not being allowed during a transaction. These do not
    complete synchronously and would therefore deadlock in a transaction.

    :param connection: The connection to iTerm2.

    :Example:

      async with iterm2.Transaction():
        do stuff
    """

    def __init__(self, connection: Connection) -> None:
        self.connection: Connection = connection

    async def __aenter__(self) -> None:
        # pylint: disable=global-statement
        global gCURRENT_TRANSACTION
        if not gCURRENT_TRANSACTION:
            gCURRENT_TRANSACTION = self

        await async_start_transaction(self.connection)

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: types.TracebackType | None,
    ) -> None:
        await async_end_transaction(self.connection)

        # pylint: disable=global-statement
        global gCURRENT_TRANSACTION
        if gCURRENT_TRANSACTION == self:
            gCURRENT_TRANSACTION = None

    @staticmethod
    def current() -> Transaction | None:
        """Returns the current transaction."""
        return gCURRENT_TRANSACTION
