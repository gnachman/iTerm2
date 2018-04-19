import asyncio
import concurrent
import iterm2.api_pb2
import time
import websockets

_helpers = []

class Connection:
  @staticmethod
  def register_helper(helper):
    """
    Registers a function that handles incoming messages.

    helper: A coroutine that will be called on incoming messages that were not
      previously handled.
    """
    global _helpers
    assert helper is not None
    _helpers.append(helper)

  def __init__(self):
    self.__deferred = None

  """
  This class holds the websocket connection to iTerm2.

  It provides the ability send and receive messages at a low level.
  """

  def run(self, coro):
    """
    Convenience method to start a program.

    Connects to the API endpoint, begins an asyncio event loop, and runs the
    passed in coroutine.

    coro: A coroutine (async function) to run after connecting.
    """
    async def main(loop):
      await self.connect(coro)
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main(loop))


  async def send_message(self, message):
    """
    Sends a message.

    This is a low-level operation that is not generally called by user code.

    message: A protocol buffer of type iterm2.api_pb2.Request to send.
    """
    await self.websocket.send(message.SerializeToString())

  async def recv_message(self):
    """
    Asynchronously receives a message.

    This is a low-level operation that is not generally called by user code.

    Returns: a protocol buffer message of type iterm2.api_pb2.Response.
    """
    data = await self.websocket.recv()
    message = iterm2.api_pb2.Response()
    message.ParseFromString(data)
    return message

  async def connect(self, coro):
    """
    Establishes a websocket connection.

    Connects to iTerm2 on localhost. Once connected, awaits execution of coro.

    coro: A coroutine to run once connected.
    """
    headers = { "origin": "ws://localhost/" }
    async with websockets.connect('ws://localhost:1912',
                                  extra_headers=headers,
                                  subprotocols=[ 'api.iterm2.com' ]) as websocket:
      self.websocket = websocket
      await coro(self)

  async def dispatch_until_id(self, reqid):
    """
    Handle incoming messages until one with the specified id is received.

    Messages not having the expected id get dispatched asynchronously by a
    registered helper if one exists.

    reqid: The request ID to look for.

    Returns: A message with the specified request id.
    """
    ownsDeferred = self._begin_deferring()
    while True:
      message = await self.recv_message()
      if message.id == reqid:
        if ownsDeferred:
          for d in self._iterate_deferred():
            self._dispatch(d)
        return message
      else:
        self._defer(message)

  async def dispatch_for_duration(self, duration):
    """
    Handle incoming messages for a fixed duration of time.

    duration: A time in seconds

    Returns after that duration.
    """
    try:
      now = time.time()
      end = now + duration
      while now < end:
        message = await asyncio.wait_for(self.recv_message(), end - now)
        await self._dispatch(message)
        now = time.time()
    except concurrent.futures._base.TimeoutError:
      return

  async def dispatch_until_future(self, future):
    """
    Handle incoming messages until a future has a result.

    future: A future that will get a result.
    """
    while not future.done():
      message = await self.recv_message()
      await self._dispatch(message)


  def _begin_deferring(self):
    """
    Enter a mode where incoming notifications are added to an array to be
    processed later.
    """
    if self.__deferred is None:
      self.__deferred = []
      return True
    else:
      return False

  def _defer(self, message):
    """
    Add message to the deferred list.
    """
    assert(self.__deferred is not None)
    self.__deferred.append(message)

  def _iterate_deferred(self):
    """
    A generator that yeilds deferred messages in the order they were added.
    """
    while len(self.__deferred) > 0:
      deferred = self.__deferred
      self.__deferred = []
      for d in self.__deferred:
        yield(d)
    self.__deferred = None

  async def _dispatch(self, message):
    """
    Dispatch a message to all registered helpers.
    """
    global _helpers

    for helper in _helpers:
      assert helper is not None
      if await helper(self, message):
        break


