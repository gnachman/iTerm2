"""
The :mod:`websockets.protocol` module handles WebSocket control and data
frames as specified in `sections 4 to 8 of RFC 6455`_.

.. _sections 4 to 8 of RFC 6455: http://tools.ietf.org/html/rfc6455#section-4

"""

import asyncio
import asyncio.queues
import codecs
import collections
import enum
import logging
import random
import struct

from .compatibility import asyncio_ensure_future
from .exceptions import (
    ConnectionClosed, InvalidState, PayloadTooBig, WebSocketProtocolError
)
from .framing import *
from .handshake import *


__all__ = ['WebSocketCommonProtocol']

logger = logging.getLogger(__name__)


# A WebSocket connection goes through the following four states, in order:

class State(enum.IntEnum):
    CONNECTING, OPEN, CLOSING, CLOSED = range(4)

# In order to ensure consistency, the code always checks the current value of
# WebSocketCommonProtocol.state before assigning a new value and never yields
# between the check and the assignment.


class WebSocketCommonProtocol(asyncio.StreamReaderProtocol):
    """
    This class implements common parts of the WebSocket protocol.

    It assumes that the WebSocket connection is established. The handshake is
    managed in subclasses such as
    :class:`~websockets.server.WebSocketServerProtocol` and
    :class:`~websockets.client.WebSocketClientProtocol`.

    It runs a task that stores incoming data frames in a queue and deals with
    control frames automatically. It sends outgoing data frames and performs
    the closing handshake.

    On Python ≥ 3.6, :class:`WebSocketCommonProtocol` instances support
    asynchronous iteration::

        async for message in websocket:
            await process(message)

    The iterator yields incoming messages. It exits normally when the
    connection is closed with the status code 1000 OK. It raises a
    :exc:`~websockets.exceptions.ConnectionClosed` exception when the
    connection is closed with any other status code.

    The ``host``, ``port`` and ``secure`` parameters are simply stored as
    attributes for handlers that need them.

    The ``timeout`` parameter defines the maximum wait time in seconds for
    completing the closing handshake and, only on the client side, for
    terminating the TCP connection. :meth:`close()` will complete in at most
    ``4 * timeout`` on the server side and ``5 * timeout`` on the client side.

    The ``max_size`` parameter enforces the maximum size for incoming messages
    in bytes. The default value is 1MB. ``None`` disables the limit. If a
    message larger than the maximum size is received, :meth:`recv()` will
    raise :exc:`~websockets.exceptions.ConnectionClosed` and the connection
    will be closed with status code 1009.

    The ``max_queue`` parameter sets the maximum length of the queue that holds
    incoming messages. The default value is 32. 0 disables the limit. Messages
    are added to an in-memory queue when they're received; then :meth:`recv()`
    pops from that queue. In order to prevent excessive memory consumption when
    messages are received faster than they can be processed, the queue must be
    bounded. If the queue fills up, the protocol stops processing incoming data
    until :meth:`recv()` is called. In this situation, various receive buffers
    (at least in ``asyncio`` and in the OS) will fill up, then the TCP receive
    window will shrink, slowing down transmission to avoid packet loss.

    Since Python can use up to 4 bytes of memory to represent a single
    character, each websocket connection may use up to ``4 * max_size *
    max_queue`` bytes of memory to store incoming messages. By default,
    this is 128MB. You may want to lower the limits, depending on your
    application's requirements.

    The ``read_limit`` argument sets the high-water limit of the buffer for
    incoming bytes. The low-water limit is half the high-water limit. The
    default value is 64kB, half of asyncio's default (based on the current
    implementation of :class:`~asyncio.StreamReader`).

    The ``write_limit`` argument sets the high-water limit of the buffer for
    outgoing bytes. The low-water limit is a quarter of the high-water limit.
    The default value is 64kB, equal to asyncio's default (based on the
    current implementation of ``FlowControlMixin``).

    As soon as the HTTP request and response in the opening handshake are
    processed, the request path is available in the :attr:`path` attribute,
    and the request and response HTTP headers are available:

    * as a :class:`~http.client.HTTPMessage` in the :attr:`request_headers`
      and :attr:`response_headers` attributes
    * as an iterable of (name, value) pairs in the :attr:`raw_request_headers`
      and :attr:`raw_response_headers` attributes

    These attributes must be treated as immutable.

    If a subprotocol was negotiated, it's available in the :attr:`subprotocol`
    attribute.

    Once the connection is closed, the status code is available in the
    :attr:`close_code` attribute and the reason in :attr:`close_reason`.

    """
    # There are only two differences between the client-side and the server-
    # side behavior: masking the payload and closing the underlying TCP
    # connection. Set is_client and side to pick a side.
    is_client = None
    side = 'undefined'

    def __init__(self, *,
                 host=None, port=None, secure=None,
                 timeout=10, max_size=2 ** 20, max_queue=2 ** 5,
                 read_limit=2 ** 16, write_limit=2 ** 16,
                 loop=None, legacy_recv=False):
        self.host = host
        self.port = port
        self.secure = secure
        self.timeout = timeout
        self.max_size = max_size
        self.max_queue = max_queue
        self.read_limit = read_limit
        self.write_limit = write_limit

        # Store a reference to loop to avoid relying on self._loop, a private
        # attribute of StreamReaderProtocol, inherited from FlowControlMixin.
        if loop is None:
            loop = asyncio.get_event_loop()
        self.loop = loop

        self.legacy_recv = legacy_recv

        # Configure read buffer limits. The high-water limit is defined by
        # ``self.read_limit``. The ``limit`` argument controls the line length
        # limit and half the buffer limit of :class:`~asyncio.StreamReader`.
        # That's why it must be set to half of ``self.read_limit``.
        stream_reader = asyncio.StreamReader(limit=read_limit // 2, loop=loop)
        super().__init__(stream_reader, self.client_connected, loop)

        self.reader = None
        self.writer = None
        self._drain_lock = asyncio.Lock(loop=loop)

        # This class implements the data transfer and closing handshake, which
        # are shared between the client-side and the server-side.
        # Subclasses implement the opening handshake and, on success, execute
        # :meth:`connection_open()` to change the state to OPEN.
        self.state = State.CONNECTING

        # HTTP protocol parameters.
        self.path = None
        self.request_headers = None
        self.raw_request_headers = None
        self.response_headers = None
        self.raw_response_headers = None

        # WebSocket protocol parameters.
        self.extensions = []
        self.subprotocol = None

        # The close code and reason are set when receiving a close frame or
        # losing the TCP connection.
        self.close_code = None
        self.close_reason = ''

        # Completed when the connection state becomes CLOSED. Translates the
        # :meth:`connection_lost()` callback to a :class:`~asyncio.Future`
        # that can be awaited. (Other :class:`~asyncio.Protocol` callbacks are
        # translated by ``self.stream_reader``).
        self.connection_lost_waiter = asyncio.Future(loop=loop)

        # Queue of received messages.
        self.messages = asyncio.queues.Queue(max_queue, loop=loop)

        # Mapping of ping IDs to waiters, in chronological order.
        self.pings = collections.OrderedDict()

        # Task running the data transfer.
        self.transfer_data_task = None

        # Task closing the TCP connection.
        self.close_connection_task = None

    def client_connected(self, reader, writer):
        """
        Callback when the TCP connection is established.

        Record references to the stream reader and the stream writer to avoid
        using private attributes ``_stream_reader`` and ``_stream_writer`` of
        :class:`~asyncio.StreamReaderProtocol`.

        """
        self.reader = reader
        self.writer = writer

    def connection_open(self):
        """
        Callback when the WebSocket opening handshake completes.

        Enter the OPEN state and start the data transfer phase.

        """
        # 4.1. The WebSocket Connection is Established.
        assert self.state is State.CONNECTING
        self.state = State.OPEN
        # Start the task that receives incoming WebSocket messages.
        self.transfer_data_task = asyncio_ensure_future(
            self.transfer_data(), loop=self.loop)
        # Start the task that eventually closes the TCP connection.
        self.close_connection_task = asyncio_ensure_future(
            self.close_connection(), loop=self.loop)

    # Public API

    @property
    def local_address(self):
        """
        Local address of the connection.

        This is a ``(host, port)`` tuple or ``None`` if the connection hasn't
        been established yet.

        """
        if self.writer is None:
            return None
        return self.writer.get_extra_info('sockname')

    @property
    def remote_address(self):
        """
        Remote address of the connection.

        This is a ``(host, port)`` tuple or ``None`` if the connection hasn't
        been established yet.

        """
        if self.writer is None:
            return None
        return self.writer.get_extra_info('peername')

    @property
    def open(self):
        """
        This property is ``True`` when the connection is usable.

        It may be used to detect disconnections but this is discouraged per
        the EAFP_ principle. When ``open`` is ``False``, using the connection
        raises a :exc:`~websockets.exceptions.ConnectionClosed` exception.

        .. _EAFP: https://docs.python.org/3/glossary.html#term-eafp

        """
        return self.state is State.OPEN

    @asyncio.coroutine
    def recv(self):
        """
        This coroutine receives the next message.

        It returns a :class:`str` for a text frame and :class:`bytes` for a
        binary frame.

        When the end of the message stream is reached, :meth:`recv` raises
        :exc:`~websockets.exceptions.ConnectionClosed`. This can happen after
        a normal connection closure, a protocol error or a network failure.

        .. versionchanged:: 3.0

            :meth:`recv` used to return ``None`` instead. Refer to the
            changelog for details.

        """
        # Don't yield from self.ensure_open() here because messages could be
        # available in the queue even if the connection is closed.

        # Return any available message
        try:
            return self.messages.get_nowait()
        except asyncio.queues.QueueEmpty:
            pass

        # Don't yield from self.ensure_open() here because messages could be
        # received before the closing frame even if the connection is closing.

        # Wait for a message until the connection is closed
        next_message = asyncio_ensure_future(
            self.messages.get(), loop=self.loop)
        try:
            done, pending = yield from asyncio.wait(
                [next_message, self.transfer_data_task],
                loop=self.loop, return_when=asyncio.FIRST_COMPLETED)
        except asyncio.CancelledError:
            # Propagate cancellation to avoid leaking the next_message Task.
            next_message.cancel()
            raise

        # Now there's no need to yield from self.ensure_open(). Either a
        # message was received or the connection was closed.

        if next_message in done:
            return next_message.result()
        else:
            next_message.cancel()
            if not self.legacy_recv:
                raise ConnectionClosed(self.close_code, self.close_reason)

    @asyncio.coroutine
    def send(self, data):
        """
        This coroutine sends a message.

        It sends :class:`str` as a text frame and :class:`bytes` as a binary
        frame. It raises a :exc:`TypeError` for other inputs.

        """
        yield from self.ensure_open()

        if isinstance(data, str):
            opcode = 1
            data = data.encode('utf-8')
        elif isinstance(data, bytes):
            opcode = 2
        else:
            raise TypeError("data must be bytes or str")

        yield from self.write_frame(opcode, data)

    @asyncio.coroutine
    def close(self, code=1000, reason=''):
        """
        This coroutine performs the closing handshake.

        It waits for the other end to complete the handshake and for the TCP
        connection to terminate.

        It doesn't do anything once the connection is closed. In other words
        it's idemptotent.

        It's safe to wrap this coroutine in :func:`~asyncio.ensure_future`
        since errors during connection termination aren't particularly useful.

        ``code`` must be an :class:`int` and ``reason`` a :class:`str`.

        """
        if self.state is State.OPEN:
            # 7.1.2. Start the WebSocket Closing Handshake
            # 7.1.3. The WebSocket Closing Handshake is Started
            frame_data = serialize_close(code, reason)
            try:
                yield from asyncio.wait_for(
                    self.write_frame(OP_CLOSE, frame_data),
                    self.timeout, loop=self.loop)
            except asyncio.TimeoutError:
                # If the close frame cannot be sent because the send buffers
                # are full, the closing handshake won't complete anyway.
                # Cancel the data transfer task to shut down faster.
                # Cancelling a task is idempotent.
                self.transfer_data_task.cancel()

        # If no close frame is received within the timeout, wait_for() cancels
        # the data transfer task and raises TimeoutError. Then transfer_data()
        # catches CancelledError and exits without an exception.

        # If close() is called multiple times concurrently and one of these
        # calls hits the timeout, other calls will resume executing without an
        # exception, so there's no need to catch CancelledError here.

        try:
            # If close() is cancelled during the wait, self.transfer_data_task
            # is cancelled before the timeout elapses (on Python ≥ 3.4.3).
            # This helps closing connections when shutting down a server.
            yield from asyncio.wait_for(
                self.transfer_data_task, self.timeout, loop=self.loop)
        except asyncio.TimeoutError:
            pass

        # Wait for the close connection task to close the TCP connection.
        yield from asyncio.shield(self.close_connection_task)

    @asyncio.coroutine
    def ping(self, data=None):
        """
        This coroutine sends a ping.

        It returns a :class:`~asyncio.Future` which will be completed when the
        corresponding pong is received and which you may ignore if you don't
        want to wait.

        A ping may serve as a keepalive or as a check that the remote endpoint
        received all messages up to this point::

            pong_waiter = await ws.ping()
            await pong_waiter   # only if you want to wait for the pong

        By default, the ping contains four random bytes. The content may be
        overridden with the optional ``data`` argument which must be of type
        :class:`str` (which will be encoded to UTF-8) or :class:`bytes`.

        """
        yield from self.ensure_open()

        if data is not None:
            data = encode_data(data)

        # Protect against duplicates if a payload is explicitly set.
        if data in self.pings:
            raise ValueError("Already waiting for a pong with the same data")

        # Generate a unique random payload otherwise.
        while data is None or data in self.pings:
            data = struct.pack('!I', random.getrandbits(32))

        self.pings[data] = asyncio.Future(loop=self.loop)

        yield from self.write_frame(OP_PING, data)

        return asyncio.shield(self.pings[data])

    @asyncio.coroutine
    def pong(self, data=b''):
        """
        This coroutine sends a pong.

        An unsolicited pong may serve as a unidirectional heartbeat.

        The content may be overridden with the optional ``data`` argument
        which must be of type :class:`str` (which will be encoded to UTF-8) or
        :class:`bytes`.

        """
        yield from self.ensure_open()

        data = encode_data(data)

        yield from self.write_frame(OP_PONG, data)

    # Private methods - no guarantees.

    @asyncio.coroutine
    def ensure_open(self):
        """
        Check that the WebSocket connection is open.

        Raise :exc:`~websockets.exceptions.ConnectionClosed` if it isn't.

        """
        # Handle cases from most common to least common for performance.
        if self.state is State.OPEN:
            return

        if self.state is State.CLOSED:
            raise ConnectionClosed(self.close_code, self.close_reason)

        if self.state is State.CLOSING:
            # If we started the closing handshake, wait for its completion to
            # get the proper close code and status. self.close_connection_task
            # will complete within 4 or 5 * timeout after calling close().
            # The CLOSING state also occurs when failing the connection. In
            # that case self.close_connection_task will complete even faster.
            if self.close_code is None:
                yield from asyncio.shield(self.close_connection_task)
            raise ConnectionClosed(self.close_code, self.close_reason)

        # Control may only reach this point in buggy third-party subclasses.
        assert self.state is State.CONNECTING
        raise InvalidState("WebSocket connection isn't established yet")

    @asyncio.coroutine
    def transfer_data(self):
        """
        Read incoming messages and put them in a queue.

        This coroutine runs in a task until the closing handshake is started.

        """
        try:
            while True:
                msg = yield from self.read_message()
                # Exit the loop when receiving a close frame.
                if msg is None:
                    break
                yield from self.messages.put(msg)
        except asyncio.CancelledError:
            # This happens if self.close() cancels self.transfer_data_task.
            pass
        except WebSocketProtocolError:
            yield from self.fail_connection(1002)
        except asyncio.IncompleteReadError:
            yield from self.fail_connection(1006)
        except UnicodeDecodeError:
            yield from self.fail_connection(1007)
        except PayloadTooBig:
            yield from self.fail_connection(1009)
        except Exception:
            logger.warning("Error in data transfer", exc_info=True)
            yield from self.fail_connection(1011)

    @asyncio.coroutine
    def read_message(self):
        """
        Read a single message from the connection.

        Re-assemble data frames if the message is fragmented.

        Return ``None`` when the closing handshake is started.

        """
        frame = yield from self.read_data_frame(max_size=self.max_size)

        # A close frame was received.
        if frame is None:
            return

        if frame.opcode == OP_TEXT:
            text = True
        elif frame.opcode == OP_BINARY:
            text = False
        else:   # frame.opcode == OP_CONT
            raise WebSocketProtocolError("Unexpected opcode")

        # Shortcut for the common case - no fragmentation
        if frame.fin:
            return frame.data.decode('utf-8') if text else frame.data

        # 5.4. Fragmentation
        chunks = []
        max_size = self.max_size
        if text:
            decoder = codecs.getincrementaldecoder('utf-8')(errors='strict')
            if max_size is None:
                def append(frame):
                    nonlocal chunks
                    chunks.append(decoder.decode(frame.data, frame.fin))
            else:
                def append(frame):
                    nonlocal chunks, max_size
                    chunks.append(decoder.decode(frame.data, frame.fin))
                    max_size -= len(frame.data)
        else:
            if max_size is None:
                def append(frame):
                    nonlocal chunks
                    chunks.append(frame.data)
            else:
                def append(frame):
                    nonlocal chunks, max_size
                    chunks.append(frame.data)
                    max_size -= len(frame.data)
        append(frame)

        while not frame.fin:
            frame = yield from self.read_data_frame(max_size=max_size)
            if frame is None:
                raise WebSocketProtocolError("Incomplete fragmented message")
            if frame.opcode != OP_CONT:
                raise WebSocketProtocolError("Unexpected opcode")
            append(frame)

        return ('' if text else b'').join(chunks)

    @asyncio.coroutine
    def read_data_frame(self, max_size):
        """
        Read a single data frame from the connection.

        Process control frames received before the next data frame.

        Return ``None`` if a close frame is encountered before any data frame.

        """
        # 6.2. Receiving Data
        while True:
            frame = yield from self.read_frame(max_size)

            # 5.5. Control Frames
            if frame.opcode == OP_CLOSE:
                # Make sure the close frame is valid before echoing it.
                code, reason = parse_close(frame.data)
                # 7.1.5.  The WebSocket Connection Close Code
                # 7.1.6.  The WebSocket Connection Close Reason
                self.close_code, self.close_reason = code, reason
                if self.state is State.OPEN:
                    # 7.1.3. The WebSocket Closing Handshake is Started
                    yield from self.write_frame(OP_CLOSE, frame.data)
                return

            elif frame.opcode == OP_PING:
                # Answer pings.
                yield from self.pong(frame.data)

            elif frame.opcode == OP_PONG:
                # Do not acknowledge pings on unsolicited pongs.
                if frame.data in self.pings:
                    # Acknowledge all pings up to the one matching this pong.
                    ping_id = None
                    while ping_id != frame.data:
                        ping_id, pong_waiter = self.pings.popitem(0)
                        pong_waiter.set_result(None)

            # 5.6. Data Frames
            else:
                return frame

    @asyncio.coroutine
    def read_frame(self, max_size):
        """
        Read a single frame from the connection.

        """
        frame = yield from Frame.read(
            self.reader.readexactly,
            mask=not self.is_client,
            max_size=max_size,
            extensions=self.extensions,
        )
        logger.debug("%s < %s", self.side, frame)
        return frame

    @asyncio.coroutine
    def write_frame(self, opcode, data=b''):
        # Defensive assertion for protocol compliance.
        if self.state is not State.OPEN:                    # pragma: no cover
            raise InvalidState("Cannot write to a WebSocket "
                               "in the {} state".format(self.state.name))

        # Make sure no other frame will be sent after a close frame. Do this
        # before yielding control to avoid sending more than one close frame.
        if opcode == OP_CLOSE:
            self.state = State.CLOSING

        frame = Frame(True, opcode, data)
        logger.debug("%s > %s", self.side, frame)
        frame.write(
            self.writer.write,
            mask=self.is_client,
            extensions=self.extensions,
        )

        # Backport of https://github.com/python/asyncio/pull/280.
        # Remove when dropping support for Python < 3.6.
        if self.writer.transport is not None:               # pragma: no cover
            if self.writer_is_closing():
                    yield

        try:
            # drain() cannot be called concurrently by multiple coroutines:
            # http://bugs.python.org/issue29930. Remove this lock when no
            # version of Python where this bugs exists is supported anymore.
            with (yield from self._drain_lock):
                # Handle flow control automatically.
                yield from self.writer.drain()
        except ConnectionError:
            # Terminate the connection if the socket died.
            yield from self.fail_connection(1006)
            # And raise an exception, since the frame couldn't be sent.
            raise ConnectionClosed(self.close_code, self.close_reason)

    def writer_is_closing(self):
        """
        Backport of https://github.com/python/asyncio/pull/291.

        Replace with ``self.writer.transport.is_closing()`` when dropping
        support for Python < 3.6 and with ``self.writer.is_closing()`` when
        https://bugs.python.org/issue31491 is fixed.

        """
        transport = self.writer.transport
        try:
            return transport.is_closing()
        except AttributeError:                              # pragma: no cover
            # This emulates what is_closing would return if it existed.
            try:
                return transport._closing
            except AttributeError:
                return transport._closed

    @asyncio.coroutine
    def close_connection(self, after_handshake=True):
        """
        7.1.1. Close the WebSocket Connection

        When the opening handshake succeeds, :meth:`connection_open` starts
        this coroutine in a task. It waits for the data transfer phase to
        complete then it closes the TCP connection cleanly.

        When the opening handshake fails, the client or the server runs this
        coroutine with ``after_handshake=False`` to close the TCP connection.

        """
        try:
            # Wait for the data transfer phase to complete.
            if after_handshake:
                yield from self.transfer_data_task

            # A client should wait for a TCP Close from the server.
            if self.is_client and after_handshake:
                if (yield from self.wait_for_connection_lost()):
                    return
                logger.debug(
                    "%s ! timed out waiting for TCP close", self.side)

            # Half-close the TCP connection if possible (when there's no TLS).
            if self.writer.can_write_eof():
                logger.debug(
                    "%s x half-closing TCP connection", self.side)
                self.writer.write_eof()

                if (yield from self.wait_for_connection_lost()):
                    return
                logger.debug(
                    "%s ! timed out waiting for TCP close", self.side)

        finally:
            # The try/finally ensures that the transport never remains open,
            # even if this coroutine is cancelled (for example).

            # Closing a transport is idempotent. If the transport was already
            # closed, for example from eof_received(), it's fine.

            # Close the TCP connection. Buffers are flushed asynchronously.
            logger.debug(
                "%s x closing TCP connection", self.side)
            self.writer.close()

            if (yield from self.wait_for_connection_lost()):
                return
            logger.debug(
                "%s ! timed out waiting for TCP close", self.side)

            # Abort the TCP connection. Buffers are discarded.
            logger.debug(
                "%s x aborting TCP connection", self.side)
            self.writer.transport.abort()

            # connection_lost() is called quickly after aborting.
            yield from self.wait_for_connection_lost()

    @asyncio.coroutine
    def wait_for_connection_lost(self):
        """
        Wait until the TCP connection is closed or ``self.timeout`` elapses.

        Return ``True`` if the connection is closed and ``False`` otherwise.

        """
        if not self.connection_lost_waiter.done():
            try:
                yield from asyncio.wait_for(
                    asyncio.shield(self.connection_lost_waiter),
                    self.timeout, loop=self.loop)
            except asyncio.TimeoutError:
                pass
        # Re-check self.connection_lost_waiter.done() synchronously because
        # connection_lost() could run between the moment the timeout occurs
        # and the moment this coroutine resumes running.
        return self.connection_lost_waiter.done()

    @asyncio.coroutine
    def fail_connection(self, code=1011, reason=''):
        """
        7.1.7. Fail the WebSocket Connection

        """
        logger.debug(
            "%s ! failing WebSocket connection: %d %s",
            self.side, code, reason,
        )
        # Don't send a close frame if the connection is broken.
        if self.state is State.OPEN and code != 1006:
            frame_data = serialize_close(code, reason)
            yield from self.write_frame(OP_CLOSE, frame_data)

    # asyncio.StreamReaderProtocol methods

    def connection_made(self, transport):
        """
        Configure write buffer limits.

        The high-water limit is defined by ``self.write_limit``.

        The low-water limit currently defaults to ``self.write_limit // 4`` in
        :meth:`~asyncio.WriteTransport.set_write_buffer_limits`, which should
        be all right for reasonable use cases of this library.

        This is the earliest point where we can get hold of the transport,
        which means it's the best point for configuring it.

        """
        logger.debug("%s - connection_made(%s)", self.side, transport)
        transport.set_write_buffer_limits(self.write_limit)
        super().connection_made(transport)

    def eof_received(self):
        """
        Close the transport after receiving EOF.

        Since Python 3.5, `:meth:~StreamReaderProtocol.eof_received` returns
        ``True`` on non-TLS connections.

        See http://bugs.python.org/issue24539 for more information.

        This is inappropriate for websockets for at least three reasons:

        1. The use case is to read data until EOF with self.reader.read(-1).
           Since websockets is a TLV protocol, this never happens.

        2. It doesn't work on TLS connections. A falsy value must be
           returned to have the same behavior on TLS and plain connections.

        3. The websockets protocol has its own closing handshake. Endpoints
           close the TCP connection after sending a Close frame.

        As a consequence we revert to the previous, more useful behavior.

        """
        logger.debug("%s - eof_received()", self.side)
        super().eof_received()
        return

    def connection_lost(self, exc):
        """
        7.1.4. The WebSocket Connection is Closed.

        """
        logger.debug("%s - connection_lost(%s)", self.side, exc)
        self.state = State.CLOSED
        if self.close_code is None:
            self.close_code = 1006
        # If self.connection_lost_waiter isn't pending, that's a bug, because:
        # - it's set only here in connection_lost() which is called only once;
        # - it must never be cancelled.
        self.connection_lost_waiter.set_result(None)
        super().connection_lost(exc)


try:
    from .py36.protocol import __aiter__
except (SyntaxError, ImportError):                          # pragma: no cover
    pass
else:
    WebSocketCommonProtocol.__aiter__ = __aiter__
