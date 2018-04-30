import asyncio
import concurrent
import iterm2.api_pb2
import os
import sys
import time
import traceback
import websockets
from iterm2._version import __version__

_helpers = []

class Connection:
  """Represents a loopback network connection from the script to iTerm2.

  Provides functionality for sending and receiving messages. Supports
  dispatching incoming messages."""

  @staticmethod
  def register_helper(helper):
    """
    Registers a function that handles incoming messages.

    You probably don't want to call this. It's used internally for dispatching
    notifications.

    Arguments:
      helper: A coroutine that will be called on incoming messages that were not
	previously handled.
    """
    global _helpers
    assert helper is not None
    _helpers.append(helper)

  def __init__(self):
    self.__deferred = None

  def run(self, coro, *args):
    """
    Convenience method to start a program.

    Connects to the API endpoint, begins an asyncio event loop, and runs the
    passed in coroutine. Exceptions will be caught and printed to stdout.

    :param coro: A coroutine (async function) to run after connecting.
    :param args: Passed to coro after its first argument (this connection).
    """
    async def main(loop):
      await self.connect(coro, *args)
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main(loop))


  async def send_message(self, message):
    """
    Sends a message.

    This is a low-level operation that is not generally called by user code.

    message: A protocol buffer of type iterm2.api_pb2.ClientOriginatedMessage to send.
    """
    await self.websocket.send(message.SerializeToString())

  async def recv_message(self):
    """
    Asynchronously receives a message.

    This is a low-level operation that is not generally called by user code.

    Returns: a protocol buffer message of type iterm2.api_pb2.ServerOriginatedMessage.
    """
    data = await self.websocket.recv()
    message = iterm2.api_pb2.ServerOriginatedMessage()
    message.ParseFromString(data)
    return message

  async def connect(self, coro, *args):
    """
    Establishes a websocket connection.

    You probably want to use Connection.run(), which takes care of runloop
    setup for you. Connects to iTerm2 on localhost. Once connected, awaits
    execution of coro.

    This uses ITERM2_COOKIE and ITERM2_KEY environment variables to help with
    authentication. ITERM2_COOKIE has a shared secret that lets user-launched
    scripts skip the auth dialog. ITERM2_KEY is used to tie together the output
    of this program with its entry in the scripting console.

    coro: A coroutine to run once connected.
    args: Passed to coro after its first argument (this connection)
    """
    cookie_key = 'ITERM2_COOKIE'
    key_key = 'ITERM2_KEY'
    headers = { "origin": "ws://localhost/" }
    if cookie_key in os.environ:
      headers["x-iterm2-cookie"] = os.environ[cookie_key]
    if key_key in os.environ:
      headers["x-iterm2-key"] = os.environ[key_key]
    headers["x-iterm2-library-version"] = "python {}".format(__version__)
    async with websockets.connect('ws://localhost:1912',
                                  extra_headers=headers,
                                  subprotocols=[ 'api.iterm2.com' ]) as websocket:
      self.websocket = websocket
      try:
        await coro(self, *args)
      except Exception as err:
        traceback.print_exc()
        sys.exit(1)


  async def dispatch_until_id(self, reqid):
    """
    Handle incoming messages until one with the specified id is received.

    Messages not having the expected id get dispatched asynchronously by a
    registered helper if one exists.

    You probably don't want to use this. It's used while waiting for the
    response to an RPC, and has logic specific that that use.

    reqid: The request ID to look for.

    Returns: A message with the specified request id.
    """
    ownsDeferred = self._begin_deferring()
    while True:
      message = await self.recv_message()
      if message.id == reqid:
        if ownsDeferred:
          for d in self._iterate_deferred():
            await self._dispatch(d)
        return message
      else:
        self._defer(message)

  async def dispatch_for_duration(self, duration):
    """
    Handle incoming messages for a fixed duration of time.

    This is typically used when you wish to receive notifications for a fixed period of time.

    :param duration: The minimum time to run while waiting for incoming messages.
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

    This is used when you wish to receive notifications indefinitely, or until
    some condition satisfied by reciving a notification is reached.

    :param future: An asyncio.Future that will get a result.
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
      for d in deferred:
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


