"""Manages the details of the websocket connection. """

import asyncio
import concurrent
import os
import sys
import time
import traceback
import websockets

import iterm2.api_pb2
from iterm2._version import __version__

def _getenv(key):
    """Gets an environment variable safely.

    Returns None if it does not exist.
    """
    if key in os.environ:
        return os.environ[key]
    else:
        return None

def _cookie_and_key():
    cookie = _getenv('ITERM2_COOKIE')
    key = _getenv('ITERM2_KEY')
    return cookie, key

def _headers():
    cookie, key = _cookie_and_key()
    headers = {"origin": "ws://localhost/",
               "x-iterm2-library-version": "python {}".format(__version__)}
    if cookie is not None:
        headers["x-iterm2-cookie"] = cookie
    if key is not None:
        headers["x-iterm2-key"] = key
    return headers

def _uri():
    return "ws://localhost:1912"

def _subprotocols():
    return ['api.iterm2.com']

class Connection:
    """Represents a loopback network connection from the script to iTerm2.

    Provides functionality for sending and receiving messages. Supports
    dispatching incoming messages."""
    helpers = []
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
        assert helper is not None
        Connection.helpers.append(helper)

    @staticmethod
    async def async_create():
        """Creates a new connection.

        This is intended for use in an apython REPL. It constructs a new
        connection and returns it without creating an asyncio event loop.
        """
        connection = Connection()
        cookie, key = _cookie_and_key()
        connection.websocket = await websockets.connect(_uri(), extra_headers=_headers(), subprotocols=_subprotocols())
        return connection

    def __init__(self):
        self.__deferred = None
        self.websocket = None
        # It is possible for multiple calls to async_recv_message() to be made.
        # For example, if you have an asyncio webserver you might want to call
        # an API in a handler while the event loop is awaiting in
        # async_recv_message. If there are two concurrent calls to
        # websocket.recv() I don't know exactly what happens but I can tell you
        # it isn't good (it looks like the second one hangs indefinitely).
        # To avoid this misfortune, this is a list of "receivers" from earliest to
        # latest. A receiver is a tuple of (matchFunc, future). The matchFunc,
        # if not None, is a function that takes a message as input and returns
        # True if it is the one and only handler for it (i.e., because it's waiting
        # for the response to an API call). When the first async_recv_message gets
        # a message from the websocket it searches __receivers for a receiver that
        # wants to handle the just-received message. If one is found, the
        # mesasge is placed in its future. Otherwise, it dispatches it itself.
        # Notifications always get dispatched by the "first" receiver, while
        # subsequent receivers should only dispatch API responses. Note that any
        # receiver may be promoted to "first receiver" status when all its predecessors
        # are done.
        self.__receivers = []
        # True while a receiver is awaiting the websocket.
        self.__awaiting_websocket = False

    def run_until_complete(self, coro):
        self.run(False, coro)

    def run_forever(self, coro):
        self.run(True, coro)

    def run(self, forever, coro):
        """
        Convenience method to start a program.

        Connects to the API endpoint, begins an asyncio event loop, and runs the
        passed in coroutine. Exceptions will be caught and printed to stdout.

        :param coro: A coroutine (async function) to run after connecting.
        """
        async def wrapper(connection):
            async def dispatch_forever():
                while True:
                    message = await self.async_recv_message()
                    await self._async_dispatch(message)
            dispatch_forever_task = asyncio.ensure_future(dispatch_forever())
            await coro(connection)
            if forever:
                await asyncio.wait([asyncio.Future()], return_when=asyncio.FIRST_COMPLETED)
            dispatch_forever_task.cancel()

        async def async_main(_loop):
            """Wrapper around the user-provided coroutine that passes it argv."""
            await self.async_connect(wrapper)
        loop = asyncio.get_event_loop()
        # This keeps you from pulling your hair out. The downside is uncertain, but
        # I do know that pulling my hair out hurts.
        loop.set_debug(True)
        self.loop = loop
        loop.run_until_complete(async_main(loop))


    async def async_send_message(self, message):
        """
        Sends a message.

        This is a low-level operation that is not generally called by user code.

        message: A protocol buffer of type iterm2.api_pb2.ClientOriginatedMessage to send.
        """
        await self.websocket.send(message.SerializeToString())

    def _receiver_index(self, message):
        """Searches __receivers for the receiver that should handle message and returns its index."""
        for i in range(len(self.__receivers)):
            matchFunc = self.__receivers[i][0]
            if matchFunc and matchFunc(message):
                return i
        # This says that the first receiver always gets the message if no other receiver can handle it.
        return 0

    def _get_receiver_future(self, message):
        """Removes the receiver for message and returns its future."""
        i = self._receiver_index(message)
        matchFunc, future = self.__receivers[i]
        del self.__receivers[i]
        return future

    async def async_recv_message(self, matchFunc=None):
        """
        Asynchronously receives a message.

        This is a low-level operation that is not generally called by user code.

        :param matchFunc: A function taking one argument (a message) that returns True if it must be handled by the caller.

        Returns: a protocol buffer message of type iterm2.api_pb2.ServerOriginatedMessage.
        """
        while True:
            # This future will be set with either a message or None. None means it's this
            # receiver's turn to start awaiting the websocket.
            my_future = asyncio.Future()
            my_receiver = (matchFunc, my_future)
            self.__receivers.append(my_receiver)

            if not self.__awaiting_websocket:
                # This one must await the websocket
                return await self._async_block_on_websocket_and_dispatch(my_future)
            else:
                # Someone else is already awaiting the websocket, so I must get in line.
                # Either another receiver will get the message I'm waiting for and hand
                # it to my future or I will become first in line and begin awaiting the
                # websocket.
                message = await self._async_wait_my_turn(my_future, matchFunc)
                if message is not None:
                    return message

    async def _async_wait_my_turn(self, my_future, matchFunc):
        """Wait for a message to be received, but do not await the websocket.

        Another receiver is awaiting the websocket. My future will get a result when
        it's time to do something.

        Returns None if it needs to be removed from receivers and re-added."""
        while not my_future.done():
            message = await my_future
            return message

    async def _async_block_on_websocket_and_dispatch(self, my_future):
        """Reads messages from the websockets and assigns them to receivers.

        Returns when my own message is received. In that case, the next in line
        (if any) gets notified that they must begin awaiting the websocket."""
        while not my_future.done():
            self.__awaiting_websocket = True
            try:
                data = await self.websocket.recv()
            except asyncio.CancelledError:
                del self.__receivers[0]
                self._wake_next_receiver_if_needed()
                raise
            finally:
                self.__awaiting_websocket = False

            message = iterm2.api_pb2.ServerOriginatedMessage()
            message.ParseFromString(data)

            future = self._get_receiver_future(message)
            future.set_result(message)
        self._wake_next_receiver_if_needed()
        return future.result()

    def _wake_next_receiver_if_needed(self):
        if self.__receivers:
            next_receiver = self.__receivers[0]
            del self.__receivers[0]
            next_receiver[1].set_result(None)

    async def async_connect(self, coro):
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
        """
        async with websockets.connect(_uri(), extra_headers=_headers(), subprotocols=_subprotocols()) as websocket:
            self.websocket = websocket
            try:
                await coro(self)
            except Exception as _err:
                traceback.print_exc()
                sys.exit(1)

    async def async_dispatch_until_id(self, reqid):
        """
        Handle incoming messages until one with the specified id is received.

        Messages not having the expected id get dispatched asynchronously by a
        registered helper if one exists.

        You probably don't want to use this. It's used while waiting for the
        response to an RPC, and has logic specific that that use.

        reqid: The request ID to look for.

        Returns: A message with the specified request id.
        """
        owns_deferred = self._begin_deferring()
        while True:
            message = await self.async_recv_message(lambda m: m.id == reqid)
            if message.id == reqid:
                if owns_deferred:
                    for deferred_message in self._iterate_deferred():
                        await self._async_dispatch(deferred_message)
                return message
            else:
                self._defer(message)

    def _begin_deferring(self):
        """
        Enter a mode where incoming notifications are added to an array to be
        processed later.
        """
        if self.__deferred is None:
            self.__deferred = []
            return True
        return False

    def _defer(self, message):
        """
        Add message to the deferred list.
        """
        assert self.__deferred is not None
        self.__deferred.append(message)

    def _iterate_deferred(self):
        """
        A generator that yeilds deferred messages in the order they were added.
        """
        while self.__deferred:
            deferred = self.__deferred
            self.__deferred = []
            for deferred_message in deferred:
                yield deferred_message
        self.__deferred = None

    async def _async_dispatch(self, message):
        """
        Dispatch a message to all registered helpers.
        """
        for helper in Connection.helpers:
            assert helper is not None
            try:
                if await helper(self, message):
                    break
            except Exception:
                raise


def run_until_complete(coro):
    """Convenience method to run an async function taking an :class:`iterm2.Connection` as an argument."""
    Connection().run_until_complete(coro)

def run_forever(coro):
    """Convenience method to run an async function taking an :class:`iterm2.Connection` as an argument."""
    Connection().run_forever(coro)
