"""Manages the details of the websocket connection. """

import asyncio
import os
import sys
import traceback
import typing
import websockets
try:
  import AppKit
  import iterm2.auth
  gAppKitAvailable = True
except:
  gAppKitAvailable = False

# websockets 9.0 moved client into legacy.client and didn't document how to
# migrate to the new API :(. Stick with the old one until I have time to deal
# with this.
try:
  import websockets.legacy.client
  websockets_client = websockets.legacy.client
except:
  websockets_client = websockets.client

import iterm2.api_pb2
from iterm2._version import __version__

def _getenv(key):
    """Gets an environment variable safely.

    Returns None if it does not exist.
    """
    if key in os.environ:
        return os.environ[key]
    return None


def _cookie_and_key():
    cookie = _getenv('ITERM2_COOKIE')
    key = _getenv('ITERM2_KEY')
    return cookie, key


def _headers():
    cookie, key = _cookie_and_key()
    headers = {"origin": "ws://localhost/",
               "x-iterm2-library-version": "python {}".format(__version__),
               "x-iterm2-disable-auth-ui": "true"}
    if cookie is not None:
        headers["x-iterm2-cookie"] = cookie
    elif gAppKitAvailable:
        headers["x-iterm2-advisory-name"] = iterm2.auth.get_script_name()
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

    helpers: typing.List[
        typing.Callable[
            ['Connection', typing.Any],
            typing.Coroutine[typing.Any, typing.Any, None]]] = []

    @staticmethod
    def register_helper(helper):
        """
        Registers a function that handles incoming messages.

        You probably don't want to call this. It's used internally for
        dispatching notifications.

        Arguments:
          helper: A coroutine that will be called on incoming messages that
              were not previously handled.
        """
        assert helper is not None
        Connection.helpers.append(helper)

    @staticmethod
    async def async_create() -> 'Connection':
        """Creates a new connection.

        This is intended for use in an apython REPL. It constructs a new
        connection and returns it without creating an asyncio event loop.

        :returns: A new connection to iTerm2.
        """
        connection = Connection()

        # Set ITERM2_COOKIE and ITERM2_KEY if needed by making an Applescript
        # request.
        have_fresh_cookie = connection.authenticate(False)

        while True:
            try:
                connection.websocket = await connection._get_connect_coro()
                # pylint: disable=protected-access
                connection.__dispatch_forever_future = asyncio.ensure_future(
                    connection._async_dispatch_forever(
                        connection, asyncio.get_event_loop()))
                return connection
            except websockets.exceptions.InvalidStatusCode as status_code_exception:
                if status_code_exception.status_code == 401:
                    if have_fresh_cookie:
                        raise
                    # Force request a cookie and try one more time.
                    connection._remove_auth()
                    have_fresh_cookie = connection.authenticate(True)
                    if not have_fresh_cookie:
                        # Didn't get a cookie, so no point trying again.
                        raise
                elif status_code_exception.status_code == 406:
                    print("This version of the iterm2 module is too old for " +
                          "the current version of iTerm2. Please upgrade.")
                    sys.exit(1)
                    raise
                else:
                    raise


    def __init__(self):
        self.websocket = None
        # A list of tuples of (match_func, future). When a message is received
        # each match_func is called with the message as an argument. The first
        # one that returns true gets its future's result set with that message.
        # If none returns True it is dispatched through the helpers. Typically
        # that would be a notification.
        self.__receivers = []
        self.__dispatch_forever_future = None
        self.__tasks = []
        self.loop = None

    def _collect_garbage(self):
        """Asyncio seems to want you to keep a reference to a task that's being
        run with ensure_future. If you don't, it says "task was destroyed but
        it is still pending". So, ok, we'll keep references around until we
        don't need to any more."""
        self.__tasks = list(filter(lambda t: not t.done(), self.__tasks))

    def run_until_complete(self, coro, retry, debug=False):
        """Runs `coro` and returns when it finishes."""
        return self.run(False, coro, retry, debug)

    def run_forever(self, coro, retry, debug=False):
        """Runs `coro` and never returns."""
        self.run(True, coro, retry, debug)

    # pylint: disable=no-self-use
    def set_message_in_future(self, loop, message, future):
        """Sets message as the future's result soon."""
        assert future is not None
        # Is the response to an RPC that is being awaited.

        def set_result():
            """If the future is not done, set its result to message."""
            assert future is not None
            if not future.done():
                future.set_result(message)

        loop.call_soon(set_result)

    async def _async_dispatch_forever(self, connection, loop):
        """
        Read messages from websocket and call helpers or message responders.
        """
        self.__tasks = []
        try:
            while True:
                data = await self.websocket.recv()
                self._collect_garbage()

                message = iterm2.api_pb2.ServerOriginatedMessage()
                message.ParseFromString(data)

                future = self._get_receiver_future(message)
                # Note that however we decide to handle this message,
                # it must be done *after* we await on the websocket.
                # Otherwise we might never get the chance.
                if future is None:
                    # May be a notification.
                    self.__tasks.append(
                        asyncio.ensure_future(
                            self._async_dispatch_to_helper(message)))
                else:
                    self.set_message_in_future(loop, message, future)
        except asyncio.CancelledError:
            # Presumably a run_until_complete script
            pass
        except:
            # I'm not quite sure why this is necessary, but if we don't
            # catch and re-raise the exception it gets swallowed.
            traceback.print_exc()
            raise

    def run(self, forever, coro, retry, debug=False):
        """
        Convenience method to start a program.

        Connects to the API endpoint, begins an asyncio event loop, and runs
        the passed in coroutine. Exceptions will be caught and printed to
        stdout.

        :param forever: Don't terminate after main returns?
        :param coro: A coroutine (async function) to run after connecting.
        :param retry: Keep trying to connect until it succeeds?
        """
        loop = asyncio.get_event_loop()

        async def async_main(connection):
            # Set __tasks here in case coro returns before
            # _async_dispatch_forever starts.
            self.__tasks = []
            dispatch_forever_task = asyncio.ensure_future(
                self._async_dispatch_forever(connection, loop))
            result = await coro(connection)
            if forever:
                await dispatch_forever_task
            dispatch_forever_task.cancel()
            # Make sure the _async_dispatch_to_helper task gets canceled to
            # avoid a warning.
            for task in self.__tasks:
                task.cancel()
            return result

        loop.set_debug(debug)
        self.loop = loop
        return loop.run_until_complete(self.async_connect(async_main, retry))

    async def async_send_message(self, message):
        """
        Sends a message.

        This is a low-level operation that is not generally called by user
        code.

        message: A protocol buffer of type
            iterm2.api_pb2.ClientOriginatedMessage to send.
        """
        await self.websocket.send(message.SerializeToString())

    def _receiver_index(self, message):
        """
        Searches __receivers for the receiver that should handle message and
        returns its index.
        """
        for i in range(len(self.__receivers)):
            match_func = self.__receivers[i][0]
            if match_func and match_func(message):
                return i
        # This says that the first receiver always gets the message if no other
        # receiver can handle it.
        return None

    def _get_receiver_future(self, message):
        """Removes the receiver for message and returns its future."""
        i = self._receiver_index(message)
        if i is None:
            return None
        match_func, future = self.__receivers[i]  # pylint: disable=unused-variable
        del self.__receivers[i]
        return future

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
        my_future = asyncio.Future()

        def match_func(incoming_message):
            return incoming_message.id == reqid

        my_receiver = (match_func, my_future)
        self.__receivers.append(my_receiver)
        return await my_future

    async def _async_dispatch_to_helper(self, message):
        """
        Dispatch a message to all registered helpers.
        """
        for helper in Connection.helpers:
            # pylint: disable=try-except-raise
            assert helper is not None
            try:
                if await helper(self, message):
                    break
            except Exception:
                raise

    @property
    def iterm2_protocol_version(self):
        """
        Returns a tuple (major version, minor version) or 0,0 if it's an old
        version of iTerm2 that doesn't report its version or it's unknown.
        """
        key = "X-iTerm2-Protocol-Version"
        if key not in self.websocket.response_headers:
            return (0, 0)
        header_value = self.websocket.response_headers[key]
        parts = header_value.split(".")
        if len(parts) != 2:
            return (0, 0)
        return (int(parts[0]), int(parts[1]))

    def _get_connect_coro(self):
        if gAppKitAvailable:
            path = self._unix_domain_socket_path()
            exists = os.path.exists(path)

            if exists:
                return self._get_unix_connect_coro()
        return self._get_tcp_connect_coro()

    def _remove_auth(self):
        # Remove these because they are not re-usable.
        vars = ["ITERM2_COOKIE", "ITERM2_KEY"]
        for var in vars:
            if var in os.environ:
                del os.environ[var]

    def _unix_domain_socket_path(self):
        applicationSupport = os.path.join(
            AppKit.NSSearchPathForDirectoriesInDomains(
                AppKit.NSApplicationSupportDirectory,
                AppKit.NSUserDomainMask,
                True)[0],
            "iTerm2")
        return os.path.join(applicationSupport, "private", "socket")

    def _get_unix_connect_coro(self):
        """Experimental: connect with unix domain socket."""
        path = self._unix_domain_socket_path()
        return websockets_client.unix_connect(
            path,
            "ws://localhost/",
            ping_interval=None,
            extra_headers=_headers(),
            subprotocols=_subprotocols())


    def _get_tcp_connect_coro(self):
        """Legacy: connect with tcp socket."""
        return websockets.connect(_uri(),
                                        ping_interval=None,
                                        extra_headers=_headers(),
                                        subprotocols=_subprotocols())

    def authenticate(self, force):
        """
        Request a cookie via Applescript.

        :param force: Remove existing cookies first?

        :returns: True if a new cookie was gotten. False if not. When `force`
            is True, then a return value of `False` means it wasn't able to
            connect. When `force` is False, a return value of `False` could
            mean either a failure to connect or that there was already a
            (possibly stale) cookie in the environment.
        """
        if not gAppKitAvailable:
            return False
        if force:
            self._remove_auth()
        try:
            return iterm2.auth.authenticate()
        except iterm2.auth.AuthenticationException:
            return False

    async def async_connect(self, coro, retry=False):
        """
        Establishes a websocket connection.

        You probably want to use Connection.run(), which takes care of runloop
        setup for you. Connects to iTerm2 on localhost. Once connected, awaits
        execution of coro.

        This uses ITERM2_COOKIE and ITERM2_KEY environment variables to help
        with authentication. ITERM2_COOKIE has a shared secret that lets
        user-launched scripts skip the auth dialog. ITERM2_KEY is used to tie
        together the output
        of this program with its entry in the scripting console.

        :param coro: A coroutine to run once connected.
        :param retry: Keep trying to connect until it succeeds?
        """
        done = False
        while not done:
            # Set ITERM2_COOKIE and ITERM2_KEY if needed by making an
            # Applescript request. This cookie might be stale, but we'll try it
            # optimstically.
            have_fresh_cookie = self.authenticate(False)

            try:
                async with self._get_connect_coro() as websocket:
                    done = True
                    self.websocket = websocket
                    # pylint: disable=broad-except
                    try:
                        return await coro(self)
                    except Exception as _err:
                        traceback.print_exc()
                        sys.exit(1)
            except websockets.exceptions.InvalidStatusCode as exception:
                if exception.status_code == 401:
                    # Auth failure.
                    if retry:
                        # Sleep and try to authenticate until successful.
                        while not have_fresh_cookie:
                            await asyncio.sleep(0.5)
                            have_fresh_cookie = self.authenticate(True)
                    else:
                        # Not retrying forever.
                        if have_fresh_cookie:
                            # Welp, that shoulda worked. Give up.
                            raise

                        # Prepare the second and final attempt.
                        self._remove_auth()
                        have_fresh_cookie = self.authenticate(True)
                        if not have_fresh_cookie:
                            # Failed to get a cookie. Give up.
                            raise
                elif exception.status_code == 406:
                    print("This version of the iterm2 module is too old " +
                          "for the current version of iTerm2. Please upgrade.")
                    sys.exit(1)
                    raise
                else:
                    raise
            except websockets.exceptions.InvalidMessage:
                # This is a temporary workaround for this issue:
                #
                # https://gitlab.com/gnachman/iterm2/issues/7681#note_163548399
                # https://github.com/aaugustin/websockets/issues/604
                #
                # I'm leaving the print statement in because I'm worried this
                # might have unexpected consequences, as InvalidMessage is
                # certainly not very specific.
                print("websockets.connect failed with InvalidMessage. " +
                      "Retrying.")
            except (ConnectionRefusedError, OSError) as exception:
                # https://github.com/aaugustin/websockets/issues/593
                if retry:
                    await asyncio.sleep(0.5)
                else:
                    print("""
There was a problem connecting to iTerm2.

Please check the following:
  * Ensure the Python API is enabled in iTerm2's preferences
  * Ensure iTerm2 is running
  * Ensure script is running on the same machine as iTerm2

If you'd prefer to retry connecting automatically instead of
raising an exception, pass retry=true to run_until_complete()
or run_forever()

""", file=sys.stderr)
                    if gAppKitAvailable:
                        path = self._unix_domain_socket_path()
                        exists = os.path.exists(path)
                        if exists:
                            print(f"If you have downgraded from iTerm2 3.3.12+ to an older version, you must\nmanually delete the file at {path}.\n", file=sys.stderr)
                    done = True
                    raise
            finally:
                self._remove_auth()


def run_until_complete(
        coro: typing.Callable[[Connection],
                              typing.Coroutine[typing.Any, typing.Any, None]],
        retry=False,
        debug=False) -> None:
    """
    Convenience method to run an async function taking an
    :class:`~iterm2.Connection` as an argument.

    After `coro` returns this function will return.

    :param coro: The coroutine to run. Must be an `async def` function. It
        should take one argument, a :class:`~iterm2.connection.Connection`, and
        does not need to return a value.
    :param retry: Keep trying to connect until it succeeds?
    """
    return Connection().run_until_complete(coro, retry, debug)


def run_forever(
        coro: typing.Callable[[Connection],
                              typing.Coroutine[typing.Any,
                                               typing.Any, None]],
        retry=False,
        debug=False) -> None:
    """
    Convenience method to run an async function taking an
    :class:`~iterm2.Connection` as an argument.

    This function never returns.

    :param coro: The coroutine to run. Must be an `async def` function. It
        should take one argument, a :class:`~iterm2.connection.Connection`, and
        does not need to return a value.
    :param retry: Keep trying to connect until it succeeds?
    """
    Connection().run_forever(coro, retry, debug)
