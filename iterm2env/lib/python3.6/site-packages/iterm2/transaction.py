import iterm2.rpc

class Transaction:
  def __init__(self, connection):
      self.connection = connection

  async def __aenter__(self):
    await iterm2.rpc.start_transaction(self.connection)

  async def __aexit__(self, exc_type, exc, tb):
    await iterm2.rpc.end_transaction(self.connection)

