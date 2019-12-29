"""Provides a class to facilitate atomic transactions."""

import typing

import iterm2.rpc
import iterm2.connection

CURRENT_TRANSACTION: typing.Optional['Transaction'] = None


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
    def __init__(self, connection: iterm2.connection.Connection):
        self.connection = connection

    async def __aenter__(self):
        # pylint: disable=global-statement
        global CURRENT_TRANSACTION
        if not CURRENT_TRANSACTION:
            CURRENT_TRANSACTION = self

        await iterm2.rpc.async_start_transaction(self.connection)

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.rpc.async_end_transaction(self.connection)

        # pylint: disable=global-statement
        global CURRENT_TRANSACTION
        if CURRENT_TRANSACTION == self:
            CURRENT_TRANSACTION = None

    @staticmethod
    def current() -> typing.Optional['Transaction']:
        """Returns the current transaction."""
        return CURRENT_TRANSACTION
