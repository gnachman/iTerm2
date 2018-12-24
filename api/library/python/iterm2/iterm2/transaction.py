"""Provides a class to facilitate atomic transactions."""

import iterm2.rpc

gCurrentTransaction = None

class Transaction:
    """An asyncio context manager for transactions.

    A transaction is a sequence of API calls that occur without anything else
    happening in between. If you're worried about state mutating between reading
    the screen contents and then sending text, for example, do it in a
    transaction and you'll know the state of the terminal will remain unchanged
    during it.

    Some APIs are noted as not being allowed during a transaction. These do not
    complete synchronously and would therefore deadlock in a transaction.

    :Example:

      async with iterm2.transaction.Transaction():
        do stuff
    """
    def __init__(self, connection):
        self.connection = connection

    async def __aenter__(self):
        global gCurrentTransaction
        if not gCurrentTransaction:
            gCurrentTransaction = self

        await iterm2.rpc.async_start_transaction(self.connection)

    async def __aexit__(self, exc_type, exc, _tb):
        await iterm2.rpc.async_end_transaction(self.connection)

        global gCurrentTransaction
        if gCurrentTransaction == self:
            gCurrentTransaction = None

    @staticmethod
    def current():
        return gCurrentTransaction

