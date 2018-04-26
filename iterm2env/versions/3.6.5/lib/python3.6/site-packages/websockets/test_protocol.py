import asyncio
import contextlib
import functools
import os
import time
import unittest
import unittest.mock

from .compatibility import asyncio_ensure_future
from .exceptions import ConnectionClosed, InvalidState
from .framing import *
from .protocol import State, WebSocketCommonProtocol


# Unit for timeouts. May be increased on slow machines by setting the
# WEBSOCKETS_TESTS_TIMEOUT_FACTOR environment variable.
MS = 0.001 * int(os.environ.get('WEBSOCKETS_TESTS_TIMEOUT_FACTOR', 1))

# asyncio's debug mode has a 10x performance penalty for this test suite.
if os.environ.get('PYTHONASYNCIODEBUG'):                    # pragma: no cover
    MS *= 10

# Ensure that timeouts are larger than the clock's resolution (for Windows).
MS = max(MS, 2.5 * time.get_clock_info('monotonic').resolution)


class TransportMock(unittest.mock.Mock):
    """
    Transport mock to control the protocol's inputs and outputs in tests.

    It calls the protocol's connection_made and connection_lost methods like
    actual transports.

    It also calls the protocol's connection_open method to bypass the
    WebSocket handshake.

    To simulate incoming data, tests call the protocol's data_received and
    eof_received methods directly.

    They could also pause_writing and resume_writing to test flow control.

    """
    # This should happen in __init__ but overriding Mock.__init__ is hard.
    def setup_mock(self, loop, protocol):
        self.loop = loop
        self.protocol = protocol
        self._eof = False
        self._closing = False
        # Simulate a successful TCP handshake.
        self.protocol.connection_made(self)
        # Simulate a successful WebSocket handshake.
        self.protocol.connection_open()

    def can_write_eof(self):
        return True

    def write_eof(self):
        # When the protocol half-closes the TCP connection, it expects the
        # other end to close it. Simulate that.
        if not self._eof:
            self.loop.call_soon(self.close)
        self._eof = True

    def is_closing(self):
        return self._closing

    def close(self):
        # Simulate how actual transports drop the connection.
        if not self._closing:
            self.loop.call_soon(self.protocol.connection_lost, None)
        self._closing = True

    def abort(self):
        # Change this to an `if` if tests call abort() multiple times.
        assert self.protocol.state is not State.CLOSED
        self.loop.call_soon(self.protocol.connection_lost, None)


class CommonTests:
    """
    Mixin that defines most tests but doesn't inherit unittest.TestCase.

    Tests are run by the ServerTests and ClientTests subclasses.

    """
    def setUp(self):
        super().setUp()
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.protocol = WebSocketCommonProtocol()
        self.transport = TransportMock()
        self.transport.setup_mock(self.loop, self.protocol)

    def tearDown(self):
        self.transport.close()
        self.loop.run_until_complete(self.protocol.close())
        self.loop.close()
        super().tearDown()

    # Utilities for writing tests.

    def run_loop_once(self):
        # Process callbacks scheduled with call_soon by appending a callback
        # to stop the event loop then running it until it hits that callback.
        self.loop.call_soon(self.loop.stop)
        self.loop.run_forever()

    def make_drain_slow(self, delay=3 * MS):
        # Process connection_made in order to initialize self.protocol.writer.
        self.run_loop_once()

        original_drain = self.protocol.writer.drain

        @asyncio.coroutine
        def delayed_drain():
            yield from asyncio.sleep(delay, loop=self.loop)
            yield from original_drain()

        self.protocol.writer.drain = delayed_drain

    close_frame = Frame(True, OP_CLOSE, serialize_close(1000, 'close'))
    local_close = Frame(True, OP_CLOSE, serialize_close(1000, 'local'))
    remote_close = Frame(True, OP_CLOSE, serialize_close(1000, 'remote'))

    @property
    def ensure_future(self):
        return functools.partial(asyncio_ensure_future, loop=self.loop)

    def receive_frame(self, frame):
        """
        Make the protocol receive a frame.

        """
        writer = self.protocol.data_received
        mask = not self.protocol.is_client
        frame.write(writer, mask=mask)

    def receive_eof(self):
        """
        Make the protocol receive the end of the data stream.

        Since ``WebSocketCommonProtocol.eof_received`` returns ``None``, an
        actual transport would close itself after calling it. This function
        emulates that behavior.

        """
        self.protocol.eof_received()
        self.loop.call_soon(self.transport.close)

    def receive_eof_if_client(self):
        """
        Like receive_eof, but only if this is the client side.

        Since the server is supposed to initiate the termination of the TCP
        connection, this method helps making tests work for both sides.

        """
        if self.protocol.is_client:
            self.receive_eof()

    def close_connection(self, code=1000, reason='close'):
        """
        Execute a closing handshake.

        This puts the connection in the CLOSED state.

        """
        close_frame_data = serialize_close(code, reason)
        # Prepare the response to the closing handshake from the remote side.
        self.receive_frame(Frame(True, OP_CLOSE, close_frame_data))
        self.receive_eof_if_client()
        # Trigger the closing handshake from the local side and complete it.
        self.loop.run_until_complete(self.protocol.close(code, reason))
        # Empty the outgoing data stream so we can make assertions later on.
        self.assertOneFrameSent(True, OP_CLOSE, close_frame_data)

    def half_close_connection_local(self, code=1000, reason='close'):
        """
        Start a closing handshake but do not complete it.

        The main difference with `close_connection` is that the connection is
        left in the CLOSING state until the event loop runs again.

        """
        close_frame_data = serialize_close(code, reason)
        # Trigger the closing handshake from the local side.
        self.ensure_future(self.protocol.close(code, reason))
        self.run_loop_once()    # wait_for executes
        self.run_loop_once()    # write_frame executes
        # Empty the outgoing data stream so we can make assertions later on.
        self.assertOneFrameSent(True, OP_CLOSE, close_frame_data)
        # Prepare the response to the closing handshake from the remote side.
        self.loop.call_soon(
            self.receive_frame, Frame(True, OP_CLOSE, close_frame_data))
        self.loop.call_soon(self.receive_eof_if_client)

    def half_close_connection_remote(self, code=1000, reason='close'):
        """
        Receive a closing handshake.

        The main difference with `close_connection` is that the connection is
        left in the CLOSING state until the event loop runs again.

        """
        close_frame_data = serialize_close(code, reason)
        # Trigger the closing handshake from the remote side.
        self.receive_frame(Frame(True, OP_CLOSE, close_frame_data))
        self.receive_eof_if_client()

    def process_invalid_frames(self):
        """
        Make the protocol fail quickly after simulating invalid data.

        To achieve this, this function triggers the protocol's eof_received,
        which interrupts pending reads waiting for more data.

        """
        self.run_loop_once()
        self.receive_eof()
        self.loop.run_until_complete(self.protocol.close_connection_task)

    def last_sent_frame(self):
        """
        Read the last frame sent to the transport.

        This method assumes that at most one frame was sent. It raises an
        AssertionError otherwise.

        """
        stream = asyncio.StreamReader(loop=self.loop)

        for (data,), kw in self.transport.write.call_args_list:
            stream.feed_data(data)
        self.transport.write.call_args_list = []
        stream.feed_eof()

        if stream.at_eof():
            frame = None
        else:
            frame = self.loop.run_until_complete(Frame.read(
                stream.readexactly, mask=self.protocol.is_client))

        if not stream.at_eof():                             # pragma: no cover
            data = self.loop.run_until_complete(stream.read())
            raise AssertionError("Trailing data found: {!r}".format(data))

        return frame

    def assertOneFrameSent(self, *args):
        self.assertEqual(self.last_sent_frame(), Frame(*args))

    def assertNoFrameSent(self):
        self.assertIsNone(self.last_sent_frame())

    def assertConnectionClosed(self, code, message):
        # The following line guarantees that connection_lost was called.
        self.assertEqual(self.protocol.state, State.CLOSED)
        # A close frame was received.
        self.assertEqual(self.protocol.close_code, code)
        self.assertEqual(self.protocol.close_reason, message)

    def assertConnectionFailed(self, code, message):
        # The following line guarantees that connection_lost was called.
        self.assertEqual(self.protocol.state, State.CLOSED)
        # No close frame was received.
        self.assertEqual(self.protocol.close_code, 1006)
        self.assertEqual(self.protocol.close_reason, '')
        # A close frame was sent -- unless the connection was already lost.
        if code == 1006:
            self.assertNoFrameSent()
        else:
            self.assertOneFrameSent(
                True, OP_CLOSE, serialize_close(code, message))

    @contextlib.contextmanager
    def assertCompletesWithin(self, min_time, max_time):
        t0 = self.loop.time()
        yield
        t1 = self.loop.time()
        dt = t1 - t0
        self.assertGreaterEqual(
            dt, min_time, "Too fast: {} < {}".format(dt, min_time))
        self.assertLess(
            dt, max_time, "Too slow: {} >= {}".format(dt, max_time))

    # Test public attributes.

    def test_local_address(self):
        get_extra_info = unittest.mock.Mock(return_value=('host', 4312))
        self.transport.get_extra_info = get_extra_info

        self.assertEqual(self.protocol.local_address, ('host', 4312))
        get_extra_info.assert_called_with('sockname', None)

    def test_local_address_before_connection(self):
        # Emulate the situation before connection_open() runs.
        self.protocol.writer, _writer = None, self.protocol.writer

        try:
            self.assertEqual(self.protocol.local_address, None)
        finally:
            self.protocol.writer = _writer

    def test_remote_address(self):
        get_extra_info = unittest.mock.Mock(return_value=('host', 4312))
        self.transport.get_extra_info = get_extra_info

        self.assertEqual(self.protocol.remote_address, ('host', 4312))
        get_extra_info.assert_called_with('peername', None)

    def test_remote_address_before_connection(self):
        # Emulate the situation before connection_open() runs.
        self.protocol.writer, _writer = None, self.protocol.writer

        try:
            self.assertEqual(self.protocol.remote_address, None)
        finally:
            self.protocol.writer = _writer

    def test_open(self):
        self.assertTrue(self.protocol.open)
        self.close_connection()
        self.assertFalse(self.protocol.open)

    # Test the recv coroutine.

    def test_recv_text(self):
        self.receive_frame(Frame(True, OP_TEXT, 'café'.encode('utf-8')))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café')

    def test_recv_binary(self):
        self.receive_frame(Frame(True, OP_BINARY, b'tea'))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, b'tea')

    def test_recv_on_closing_connection_local(self):
        self.half_close_connection_local()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.recv())

    def test_recv_on_closing_connection_remote(self):
        self.half_close_connection_remote()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.recv())

    def test_recv_on_closed_connection(self):
        self.close_connection()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.recv())

    def test_recv_protocol_error(self):
        self.receive_frame(Frame(True, OP_CONT, 'café'.encode('utf-8')))
        self.process_invalid_frames()
        self.assertConnectionFailed(1002, '')

    def test_recv_unicode_error(self):
        self.receive_frame(Frame(True, OP_TEXT, 'café'.encode('latin-1')))
        self.process_invalid_frames()
        self.assertConnectionFailed(1007, '')

    def test_recv_text_payload_too_big(self):
        self.protocol.max_size = 1024
        self.receive_frame(Frame(True, OP_TEXT, 'café'.encode('utf-8') * 205))
        self.process_invalid_frames()
        self.assertConnectionFailed(1009, '')

    def test_recv_binary_payload_too_big(self):
        self.protocol.max_size = 1024
        self.receive_frame(Frame(True, OP_BINARY, b'tea' * 342))
        self.process_invalid_frames()
        self.assertConnectionFailed(1009, '')

    def test_recv_text_no_max_size(self):
        self.protocol.max_size = None       # for test coverage
        self.receive_frame(Frame(True, OP_TEXT, 'café'.encode('utf-8') * 205))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café' * 205)

    def test_recv_binary_no_max_size(self):
        self.protocol.max_size = None       # for test coverage
        self.receive_frame(Frame(True, OP_BINARY, b'tea' * 342))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, b'tea' * 342)

    def test_recv_other_error(self):
        @asyncio.coroutine
        def read_message():
            raise Exception("BOOM")
        self.protocol.read_message = read_message
        self.process_invalid_frames()
        self.assertConnectionFailed(1011, '')

    def test_recv_cancelled(self):
        recv = self.ensure_future(self.protocol.recv())
        self.loop.call_soon(recv.cancel)
        with self.assertRaises(asyncio.CancelledError):
            self.loop.run_until_complete(recv)

        # The next frame doesn't disappear in a vacuum (it used to).
        self.receive_frame(Frame(True, OP_TEXT, 'café'.encode('utf-8')))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café')

    # Test the send coroutine.

    def test_send_text(self):
        self.loop.run_until_complete(self.protocol.send('café'))
        self.assertOneFrameSent(True, OP_TEXT, 'café'.encode('utf-8'))

    def test_send_binary(self):
        self.loop.run_until_complete(self.protocol.send(b'tea'))
        self.assertOneFrameSent(True, OP_BINARY, b'tea')

    def test_send_type_error(self):
        with self.assertRaises(TypeError):
            self.loop.run_until_complete(self.protocol.send(42))
        self.assertNoFrameSent()

    def test_send_on_closing_connection_local(self):
        self.half_close_connection_local()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.send('foobar'))
        self.assertNoFrameSent()

    def test_send_on_closing_connection_remote(self):
        self.half_close_connection_remote()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.send('foobar'))
        self.assertOneFrameSent(True, OP_CLOSE, serialize_close(1000, 'close'))

    def test_send_on_closed_connection(self):
        self.close_connection()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.send('foobar'))
        self.assertNoFrameSent()

    # Test the ping coroutine.

    def test_ping_default(self):
        self.loop.run_until_complete(self.protocol.ping())
        # With our testing tools, it's more convenient to extract the expected
        # ping data from the library's internals than from the frame sent.
        ping_data = next(iter(self.protocol.pings))
        self.assertIsInstance(ping_data, bytes)
        self.assertEqual(len(ping_data), 4)
        self.assertOneFrameSent(True, OP_PING, ping_data)

    def test_ping_text(self):
        self.loop.run_until_complete(self.protocol.ping('café'))
        self.assertOneFrameSent(True, OP_PING, 'café'.encode('utf-8'))

    def test_ping_binary(self):
        self.loop.run_until_complete(self.protocol.ping(b'tea'))
        self.assertOneFrameSent(True, OP_PING, b'tea')

    def test_ping_type_error(self):
        with self.assertRaises(TypeError):
            self.loop.run_until_complete(self.protocol.ping(42))
        self.assertNoFrameSent()

    def test_ping_on_closing_connection_local(self):
        self.half_close_connection_local()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.ping())
        self.assertNoFrameSent()

    def test_ping_on_closing_connection_remote(self):
        self.half_close_connection_remote()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.ping())
        self.assertOneFrameSent(True, OP_CLOSE, serialize_close(1000, 'close'))

    def test_ping_on_closed_connection(self):
        self.close_connection()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.ping())
        self.assertNoFrameSent()

    # Test the pong coroutine.

    def test_pong_default(self):
        self.loop.run_until_complete(self.protocol.pong())
        self.assertOneFrameSent(True, OP_PONG, b'')

    def test_pong_text(self):
        self.loop.run_until_complete(self.protocol.pong('café'))
        self.assertOneFrameSent(True, OP_PONG, 'café'.encode('utf-8'))

    def test_pong_binary(self):
        self.loop.run_until_complete(self.protocol.pong(b'tea'))
        self.assertOneFrameSent(True, OP_PONG, b'tea')

    def test_pong_type_error(self):
        with self.assertRaises(TypeError):
            self.loop.run_until_complete(self.protocol.pong(42))
        self.assertNoFrameSent()

    def test_pong_on_closing_connection_local(self):
        self.half_close_connection_local()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.pong())
        self.assertNoFrameSent()

    def test_pong_on_closing_connection_remote(self):
        self.half_close_connection_remote()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.pong())
        self.assertOneFrameSent(True, OP_CLOSE, serialize_close(1000, 'close'))

    def test_pong_on_closed_connection(self):
        self.close_connection()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.pong())
        self.assertNoFrameSent()

    # Test the protocol's logic for acknowledging pings with pongs.

    def test_answer_ping(self):
        self.receive_frame(Frame(True, OP_PING, b'test'))
        self.run_loop_once()
        self.assertOneFrameSent(True, OP_PONG, b'test')

    def test_ignore_pong(self):
        self.receive_frame(Frame(True, OP_PONG, b'test'))
        self.run_loop_once()
        self.assertNoFrameSent()

    def test_acknowledge_ping(self):
        ping = self.loop.run_until_complete(self.protocol.ping())
        self.assertFalse(ping.done())
        ping_frame = self.last_sent_frame()
        pong_frame = Frame(True, OP_PONG, ping_frame.data)
        self.receive_frame(pong_frame)
        self.run_loop_once()
        self.run_loop_once()
        self.assertTrue(ping.done())

    def test_acknowledge_previous_pings(self):
        pings = [(
            self.loop.run_until_complete(self.protocol.ping()),
            self.last_sent_frame(),
        ) for i in range(3)]
        # Unsolicited pong doesn't acknowledge pings
        self.receive_frame(Frame(True, OP_PONG, b''))
        self.run_loop_once()
        self.run_loop_once()
        self.assertFalse(pings[0][0].done())
        self.assertFalse(pings[1][0].done())
        self.assertFalse(pings[2][0].done())
        # Pong acknowledges all previous pings
        self.receive_frame(Frame(True, OP_PONG, pings[1][1].data))
        self.run_loop_once()
        self.run_loop_once()
        self.assertTrue(pings[0][0].done())
        self.assertTrue(pings[1][0].done())
        self.assertFalse(pings[2][0].done())

    def test_cancel_ping(self):
        ping = self.loop.run_until_complete(self.protocol.ping())
        ping_frame = self.last_sent_frame()
        ping.cancel()
        pong_frame = Frame(True, OP_PONG, ping_frame.data)
        self.receive_frame(pong_frame)
        self.run_loop_once()
        self.run_loop_once()
        self.assertTrue(ping.cancelled())

    def test_duplicate_ping(self):
        self.loop.run_until_complete(self.protocol.ping(b'foobar'))
        self.assertOneFrameSent(True, OP_PING, b'foobar')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(self.protocol.ping(b'foobar'))
        self.assertNoFrameSent()

    # Test the protocol's logic for rebuilding fragmented messages.

    def test_fragmented_text(self):
        self.receive_frame(Frame(False, OP_TEXT, 'ca'.encode('utf-8')))
        self.receive_frame(Frame(True, OP_CONT, 'fé'.encode('utf-8')))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café')

    def test_fragmented_binary(self):
        self.receive_frame(Frame(False, OP_BINARY, b't'))
        self.receive_frame(Frame(False, OP_CONT, b'e'))
        self.receive_frame(Frame(True, OP_CONT, b'a'))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, b'tea')

    def test_fragmented_text_payload_too_big(self):
        self.protocol.max_size = 1024
        self.receive_frame(Frame(False, OP_TEXT, 'café'.encode('utf-8') * 100))
        self.receive_frame(Frame(True, OP_CONT, 'café'.encode('utf-8') * 105))
        self.process_invalid_frames()
        self.assertConnectionFailed(1009, '')

    def test_fragmented_binary_payload_too_big(self):
        self.protocol.max_size = 1024
        self.receive_frame(Frame(False, OP_BINARY, b'tea' * 171))
        self.receive_frame(Frame(True, OP_CONT, b'tea' * 171))
        self.process_invalid_frames()
        self.assertConnectionFailed(1009, '')

    def test_fragmented_text_no_max_size(self):
        self.protocol.max_size = None       # for test coverage
        self.receive_frame(Frame(False, OP_TEXT, 'café'.encode('utf-8') * 100))
        self.receive_frame(Frame(True, OP_CONT, 'café'.encode('utf-8') * 105))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café' * 205)

    def test_fragmented_binary_no_max_size(self):
        self.protocol.max_size = None       # for test coverage
        self.receive_frame(Frame(False, OP_BINARY, b'tea' * 171))
        self.receive_frame(Frame(True, OP_CONT, b'tea' * 171))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, b'tea' * 342)

    def test_control_frame_within_fragmented_text(self):
        self.receive_frame(Frame(False, OP_TEXT, 'ca'.encode('utf-8')))
        self.receive_frame(Frame(True, OP_PING, b''))
        self.receive_frame(Frame(True, OP_CONT, 'fé'.encode('utf-8')))
        data = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(data, 'café')
        self.assertOneFrameSent(True, OP_PONG, b'')

    def test_unterminated_fragmented_text(self):
        self.receive_frame(Frame(False, OP_TEXT, 'ca'.encode('utf-8')))
        # Missing the second part of the fragmented frame.
        self.receive_frame(Frame(True, OP_BINARY, b'tea'))
        self.process_invalid_frames()
        self.assertConnectionFailed(1002, '')

    def test_close_handshake_in_fragmented_text(self):
        self.receive_frame(Frame(False, OP_TEXT, 'ca'.encode('utf-8')))
        self.receive_frame(Frame(True, OP_CLOSE, b''))
        self.process_invalid_frames()
        # The RFC may have overlooked this case: it says that control frames
        # can be interjected in the middle of a fragmented message and that a
        # close frame must be echoed. Even though there's an unterminated
        # message, technically, the closing handshake was successful.
        self.assertConnectionClosed(1005, '')

    def test_connection_close_in_fragmented_text(self):
        self.receive_frame(Frame(False, OP_TEXT, 'ca'.encode('utf-8')))
        self.process_invalid_frames()
        self.assertConnectionFailed(1006, '')

    # Test miscellaneous code paths to ensure full coverage.

    def test_connection_lost(self):
        # Test calling connection_lost without going through close_connection.
        self.protocol.connection_lost(None)

        self.assertConnectionFailed(1006, '')

    def test_ensure_connection_before_opening_handshake(self):
        # Simulate a bug by forcibly reverting the protocol state.
        self.protocol.state = State.CONNECTING

        with self.assertRaises(InvalidState):
            self.loop.run_until_complete(self.protocol.ensure_open())

    def test_legacy_recv(self):
        # By default legacy_recv in disabled.
        self.assertEqual(self.protocol.legacy_recv, False)

        self.close_connection()

        # Enable legacy_recv.
        self.protocol.legacy_recv = True

        # Now recv() returns None instead of raising ConnectionClosed.
        self.assertIsNone(self.loop.run_until_complete(self.protocol.recv()))

    def test_connection_closed_attributes(self):
        self.close_connection()

        with self.assertRaises(ConnectionClosed) as context:
            self.loop.run_until_complete(self.protocol.recv())

        connection_closed_exc = context.exception
        self.assertEqual(connection_closed_exc.code, 1000)
        self.assertEqual(connection_closed_exc.reason, 'close')

    # Test the protocol logic for closing the connection.

    def test_local_close(self):
        # Emulate how the remote endpoint answers the closing handshake.
        self.loop.call_later(MS, self.receive_frame, self.close_frame)
        self.loop.call_later(MS, self.receive_eof_if_client)

        # Run the closing handshake.
        self.loop.run_until_complete(self.protocol.close(reason='close'))

        self.assertConnectionClosed(1000, 'close')
        self.assertOneFrameSent(*self.close_frame)

        # Closing the connection again is a no-op.
        self.loop.run_until_complete(self.protocol.close(reason='oh noes!'))

        self.assertConnectionClosed(1000, 'close')
        self.assertNoFrameSent()

    def test_remote_close(self):
        # Emulate how the remote endpoint initiates the closing handshake.
        self.loop.call_later(MS, self.receive_frame, self.close_frame)
        self.loop.call_later(MS, self.receive_eof_if_client)

        # Wait for some data in order to process the handshake.
        # After recv() raises ConnectionClosed, the connection is closed.
        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.protocol.recv())

        self.assertConnectionClosed(1000, 'close')
        self.assertOneFrameSent(*self.close_frame)

        # Closing the connection again is a no-op.
        self.loop.run_until_complete(self.protocol.close(reason='oh noes!'))

        self.assertConnectionClosed(1000, 'close')
        self.assertNoFrameSent()

    def test_simultaneous_close(self):
        # Delay the incoming close frame until after we send the outgoing one.
        self.loop.call_later(MS, self.receive_frame, self.remote_close)
        self.loop.call_later(MS, self.receive_eof_if_client)

        self.loop.run_until_complete(self.protocol.close(reason='local'))

        # The close code and reason are taken from the remote side because
        # that's presumably more useful that the values from the local side.
        self.assertConnectionClosed(1000, 'remote')
        self.assertOneFrameSent(*self.local_close)

    def test_close_preserves_incoming_frames(self):
        self.receive_frame(Frame(True, OP_TEXT, b'hello'))

        self.loop.call_later(MS, self.receive_frame, self.close_frame)
        self.loop.call_later(MS, self.receive_eof_if_client)
        self.loop.run_until_complete(self.protocol.close(reason='close'))

        self.assertConnectionClosed(1000, 'close')
        self.assertOneFrameSent(*self.close_frame)

        next_message = self.loop.run_until_complete(self.protocol.recv())
        self.assertEqual(next_message, 'hello')

    def test_close_protocol_error(self):
        invalid_close_frame = Frame(True, OP_CLOSE, b'\x00')
        self.receive_frame(invalid_close_frame)
        self.receive_eof_if_client()
        self.run_loop_once()
        self.loop.run_until_complete(self.protocol.close(reason='close'))

        self.assertConnectionFailed(1002, '')

    def test_close_connection_lost(self):
        self.receive_eof()
        self.run_loop_once()
        self.loop.run_until_complete(self.protocol.close(reason='close'))

        self.assertConnectionFailed(1006, '')

    def test_local_close_during_recv(self):
        recv = self.ensure_future(self.protocol.recv())

        self.loop.call_later(MS, self.receive_frame, self.close_frame)
        self.loop.call_later(MS, self.receive_eof_if_client)

        self.loop.run_until_complete(self.protocol.close(reason='close'))

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(recv)

        self.assertConnectionClosed(1000, 'close')

    # There is no test_remote_close_during_recv because it would be identical
    # to test_remote_close.

    def test_remote_close_during_send(self):
        self.make_drain_slow()
        send = self.ensure_future(self.protocol.send('hello'))

        self.receive_frame(self.close_frame)
        self.receive_eof()

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(send)

        self.assertConnectionClosed(1000, 'close')

    # There is no test_local_close_during_send because this cannot really
    # happen, considering that writes are serialized.


class ServerTests(CommonTests, unittest.TestCase):

    def setUp(self):
        super().setUp()
        self.protocol.is_client = False
        self.protocol.side = 'server'

    def test_local_close_send_close_frame_timeout(self):
        self.protocol.timeout = 10 * MS
        self.make_drain_slow(50 * MS)
        # If we can't send a close frame, time out in 10ms.
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(9 * MS, 19 * MS):
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1006, '')

    def test_local_close_receive_close_frame_timeout(self):
        self.protocol.timeout = 10 * MS
        # If the client doesn't send a close frame, time out in 10ms.
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(9 * MS, 19 * MS):
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1006, '')

    def test_local_close_connection_lost_timeout_after_write_eof(self):
        self.protocol.timeout = 10 * MS
        # If the client doesn't close its side of the TCP connection after we
        # half-close our side with write_eof(), time out in 10ms.
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(9 * MS, 19 * MS):
            # HACK: disable write_eof => other end drops connection emulation.
            self.transport._eof = True
            self.receive_frame(self.close_frame)
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1000, 'close')

    def test_local_close_connection_lost_timeout_after_close(self):
        self.protocol.timeout = 10 * MS
        # If the client doesn't close its side of the TCP connection after we
        # half-close our side with write_eof() and close it with close(), time
        # out in 20ms.
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(19 * MS, 29 * MS):
            # HACK: disable write_eof => other end drops connection emulation.
            self.transport._eof = True
            # HACK: disable close => other end drops connection emulation.
            self.transport._closing = True
            self.receive_frame(self.close_frame)
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1000, 'close')


class ClientTests(CommonTests, unittest.TestCase):

    def setUp(self):
        super().setUp()
        self.protocol.is_client = True
        self.protocol.side = 'client'

    def test_local_close_send_close_frame_timeout(self):
        self.protocol.timeout = 10 * MS
        self.make_drain_slow(50 * MS)
        # If we can't send a close frame, time out in 20ms.
        # - 10ms waiting for sending a close frame
        # - 10ms waiting for receiving a half-close
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(19 * MS, 29 * MS):
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1006, '')

    def test_local_close_receive_close_frame_timeout(self):
        self.protocol.timeout = 10 * MS
        # If the server doesn't send a close frame, time out in 20ms:
        # - 10ms waiting for receiving a close frame
        # - 10ms waiting for receiving a half-close
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(19 * MS, 29 * MS):
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1006, '')

    def test_local_close_connection_lost_timeout_after_write_eof(self):
        self.protocol.timeout = 10 * MS
        # If the server doesn't half-close its side of the TCP connection
        # after we send a close frame, time out in 20ms:
        # - 10ms waiting for receiving a half-close
        # - 10ms waiting for receiving a close after write_eof
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(19 * MS, 29 * MS):
            # HACK: disable write_eof => other end drops connection emulation.
            self.transport._eof = True
            self.receive_frame(self.close_frame)
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1000, 'close')

    def test_local_close_connection_lost_timeout_after_close(self):
        self.protocol.timeout = 10 * MS
        # If the client doesn't close its side of the TCP connection after we
        # half-close our side with write_eof() and close it with close(), time
        # out in 20ms.
        # - 10ms waiting for receiving a half-close
        # - 10ms waiting for receiving a close after write_eof
        # - 10ms waiting for receiving a close after close
        # Check the timing within -1/+9ms for robustness.
        with self.assertCompletesWithin(29 * MS, 39 * MS):
            # HACK: disable write_eof => other end drops connection emulation.
            self.transport._eof = True
            # HACK: disable close => other end drops connection emulation.
            self.transport._closing = True
            self.receive_frame(self.close_frame)
            self.loop.run_until_complete(self.protocol.close(reason='close'))
        self.assertConnectionClosed(1000, 'close')
