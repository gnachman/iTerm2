import asyncio
import contextlib
import functools
import logging
import os.path
import random
import socket
import ssl
import sys
import tempfile
import unittest
import unittest.mock
import urllib.request

from .client import *
from .compatibility import FORBIDDEN, OK, UNAUTHORIZED
from .exceptions import (
    ConnectionClosed, InvalidHandshake, InvalidStatusCode, NegotiationError
)
from .extensions.permessage_deflate import (
    ClientPerMessageDeflateFactory, PerMessageDeflate,
    ServerPerMessageDeflateFactory
)
from .handshake import build_response
from .http import USER_AGENT, read_response
from .server import *


# Avoid displaying stack traces at the ERROR logging level.
logging.basicConfig(level=logging.CRITICAL)

testcert = os.path.join(os.path.dirname(__file__), 'test_localhost.pem')


@asyncio.coroutine
def handler(ws, path):
    if path == '/attributes':
        yield from ws.send(repr((ws.host, ws.port, ws.secure)))
    elif path == '/path':
        yield from ws.send(str(ws.path))
    elif path == '/headers':
        yield from ws.send(str(ws.request_headers))
        yield from ws.send(str(ws.response_headers))
    elif path == '/raw_headers':
        yield from ws.send(repr(ws.raw_request_headers))
        yield from ws.send(repr(ws.raw_response_headers))
    elif path == '/extensions':
        yield from ws.send(repr(ws.extensions))
    elif path == '/subprotocol':
        yield from ws.send(repr(ws.subprotocol))
    else:
        yield from ws.send((yield from ws.recv()))


@contextlib.contextmanager
def temp_test_server(test, **kwds):
    test.start_server(**kwds)
    try:
        yield
    finally:
        test.stop_server()


@contextlib.contextmanager
def temp_test_client(test, *args, **kwds):
    test.start_client(*args, **kwds)
    try:
        yield
    finally:
        test.stop_client()


def with_manager(manager, *args, **kwds):
    """
    Return a decorator that wraps a function with a context manager.

    """
    def decorate(func):
        @functools.wraps(func)
        def _decorate(self, *_args, **_kwds):
            with manager(self, *args, **kwds):
                return func(self, *_args, **_kwds)

        return _decorate

    return decorate


def with_server(**kwds):
    """
    Return a decorator for TestCase methods that starts and stops a server.

    """
    return with_manager(temp_test_server, **kwds)


def with_client(*args, **kwds):
    """
    Return a decorator for TestCase methods that starts and stops a client.

    """
    return with_manager(temp_test_client, *args, **kwds)


def get_server_uri(server, secure=False, resource_name='/'):
    """
    Return a WebSocket URI for connecting to the given server.

    """
    proto = 'wss' if secure else 'ws'

    # Pick a random socket in order to test both IPv4 and IPv6 on systems
    # where both are available. Randomizing tests is usually a bad idea. If
    # needed, either use the first socket, or test separately IPv4 and IPv6.
    server_socket = random.choice(server.sockets)

    # That case
    if server_socket.family == socket.AF_INET6:             # pragma: no cover
        host, port = server_socket.getsockname()[:2]
        host = '[{}]'.format(host)
    elif server_socket.family == socket.AF_INET:
        host, port = server_socket.getsockname()
    elif server_socket.family == socket.AF_UNIX:
        # The host and port are ignored when connecting to a Unix socket.
        host, port = 'localhost', 0
    else:                                                   # pragma: no cover
        raise ValueError("Expected an IPv6, IPv4, or Unix socket")

    return '{}://{}:{}{}'.format(proto, host, port, resource_name)


class UnauthorizedServerProtocol(WebSocketServerProtocol):

    @asyncio.coroutine
    def process_request(self, path, request_headers):
        return UNAUTHORIZED, []


class ForbiddenServerProtocol(WebSocketServerProtocol):

    @asyncio.coroutine
    def process_request(self, path, request_headers):
        return FORBIDDEN, []


class HealthCheckServerProtocol(WebSocketServerProtocol):

    @asyncio.coroutine
    def process_request(self, path, request_headers):
        if path == '/__health__/':
            body = b'status = green\n'
            return OK, [('Content-Length', str(len(body)))], body


class FooClientProtocol(WebSocketClientProtocol):
    pass


class BarClientProtocol(WebSocketClientProtocol):
    pass


class ClientNoOpExtensionFactory:
    name = 'x-no-op'

    def get_request_params(self):
        return []

    def process_response_params(self, params, accepted_extensions):
        if params:
            raise NegotiationError()
        return NoOpExtension()


class ServerNoOpExtensionFactory:
    name = 'x-no-op'

    def __init__(self, params=None):
        self.params = params or []

    def process_request_params(self, params, accepted_extensions):
        return self.params, NoOpExtension()


class NoOpExtension:
    name = 'x-no-op'

    def __repr__(self):
        return 'NoOpExtension()'

    def decode(self, frame):
        return frame

    def encode(self, frame):
        return frame


class ClientServerTests(unittest.TestCase):

    secure = False

    def setUp(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

    def tearDown(self):
        self.loop.close()

    def run_loop_once(self):
        # Process callbacks scheduled with call_soon by appending a callback
        # to stop the event loop then running it until it hits that callback.
        self.loop.call_soon(self.loop.stop)
        self.loop.run_forever()

    def start_server(self, **kwds):
        # Don't enable compression by default in tests.
        kwds.setdefault('compression', None)
        start_server = serve(handler, 'localhost', 0, **kwds)
        self.server = self.loop.run_until_complete(start_server)

    def start_client(self, resource_name='/', **kwds):
        # Don't enable compression by default in tests.
        kwds.setdefault('compression', None)
        secure = kwds.get('ssl') is not None
        server_uri = get_server_uri(self.server, secure, resource_name)
        start_client = connect(server_uri, **kwds)
        self.client = self.loop.run_until_complete(start_client)

    def stop_client(self):
        try:
            self.loop.run_until_complete(
                asyncio.wait_for(self.client.close_connection_task, timeout=1))
        except asyncio.TimeoutError:                # pragma: no cover
            self.fail("Client failed to stop")

    def stop_server(self):
        self.server.close()
        try:
            self.loop.run_until_complete(
                asyncio.wait_for(self.server.wait_closed(), timeout=1))
        except asyncio.TimeoutError:                # pragma: no cover
            self.fail("Server failed to stop")

    @contextlib.contextmanager
    def temp_server(self, **kwds):
        with temp_test_server(self, **kwds):
            yield

    @contextlib.contextmanager
    def temp_client(self, *args, **kwds):
        with temp_test_client(self, *args, **kwds):
            yield

    @with_server()
    @with_client()
    def test_basic(self):
        self.loop.run_until_complete(self.client.send("Hello!"))
        reply = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(reply, "Hello!")

    def test_server_close_while_client_connected(self):
        with self.temp_server(loop=self.loop):
            self.start_client()
        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(self.client.recv())
        # Connection ends with 1001 going away.
        self.assertEqual(self.client.close_code, 1001)

    def test_explicit_event_loop(self):
        with self.temp_server(loop=self.loop):
            with self.temp_client(loop=self.loop):
                self.loop.run_until_complete(self.client.send("Hello!"))
                reply = self.loop.run_until_complete(self.client.recv())
                self.assertEqual(reply, "Hello!")

    # The way the legacy SSL implementation wraps sockets makes it extremely
    # hard to write a test for Python 3.4.
    @unittest.skipIf(
        sys.version_info[:2] <= (3, 4), 'this test requires Python 3.5+')
    @with_server()
    def test_explicit_socket(self):

        class TrackedSocket(socket.socket):
            def __init__(self, *args, **kwargs):
                self.used_for_read = False
                self.used_for_write = False
                super().__init__(*args, **kwargs)

            def recv(self, *args, **kwargs):
                self.used_for_read = True
                return super().recv(*args, **kwargs)

            def send(self, *args, **kwargs):
                self.used_for_write = True
                return super().send(*args, **kwargs)

        server_socket = [
            s for s in self.server.sockets if s.family == socket.AF_INET][0]
        client_socket = TrackedSocket(socket.AF_INET, socket.SOCK_STREAM)
        client_socket.connect(server_socket.getsockname())

        try:
            self.assertFalse(client_socket.used_for_read)
            self.assertFalse(client_socket.used_for_write)

            with self.temp_client(
                sock=client_socket,
                server_hostname='localhost' if self.secure else None,
            ):
                self.loop.run_until_complete(self.client.send("Hello!"))
                reply = self.loop.run_until_complete(self.client.recv())
                self.assertEqual(reply, "Hello!")

            self.assertTrue(client_socket.used_for_read)
            self.assertTrue(client_socket.used_for_write)

        finally:
            client_socket.close()

    @unittest.skipUnless(
        hasattr(socket, 'AF_UNIX'), 'this test requires Unix sockets')
    def test_unix_socket(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = os.path.join(temp_dir, 'websockets')

            # Like self.start_server() but with unix_serve().
            unix_server = unix_serve(handler, path)
            self.server = self.loop.run_until_complete(unix_server)

            client_socket = socket.socket(socket.AF_UNIX)
            client_socket.connect(path)

            try:
                with self.temp_client(sock=client_socket):
                    self.loop.run_until_complete(self.client.send("Hello!"))
                    reply = self.loop.run_until_complete(self.client.recv())
                    self.assertEqual(reply, "Hello!")

            finally:
                client_socket.close()
                self.stop_server()

    @with_server()
    @with_client('/attributes')
    def test_protocol_attributes(self):
        # The test could be connecting with IPv6 or IPv4.
        expected_client_attrs = [
            server_socket.getsockname()[:2] + (self.secure,)
            for server_socket in self.server.sockets
        ]
        client_attrs = (self.client.host, self.client.port, self.client.secure)
        self.assertIn(client_attrs, expected_client_attrs)

        expected_server_attrs = ('localhost', 0, self.secure)
        server_attrs = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_attrs, repr(expected_server_attrs))

    @with_server()
    @with_client('/path')
    def test_protocol_path(self):
        client_path = self.client.path
        self.assertEqual(client_path, '/path')
        server_path = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_path, '/path')

    @with_server()
    @with_client('/headers')
    def test_protocol_headers(self):
        client_req = self.client.request_headers
        client_resp = self.client.response_headers
        self.assertEqual(client_req['User-Agent'], USER_AGENT)
        self.assertEqual(client_resp['Server'], USER_AGENT)
        server_req = self.loop.run_until_complete(self.client.recv())
        server_resp = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_req, str(client_req))
        self.assertEqual(server_resp, str(client_resp))

    @with_server()
    @with_client('/raw_headers')
    def test_protocol_raw_headers(self):
        client_req = self.client.raw_request_headers
        client_resp = self.client.raw_response_headers
        self.assertEqual(dict(client_req)['User-Agent'], USER_AGENT)
        self.assertEqual(dict(client_resp)['Server'], USER_AGENT)
        server_req = self.loop.run_until_complete(self.client.recv())
        server_resp = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_req, repr(client_req))
        self.assertEqual(server_resp, repr(client_resp))

    @with_server()
    @with_client('/raw_headers', extra_headers={'X-Spam': 'Eggs'})
    def test_protocol_custom_request_headers_dict(self):
        req_headers = self.loop.run_until_complete(self.client.recv())
        self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", req_headers)

    @with_server()
    @with_client('/raw_headers', extra_headers=[('X-Spam', 'Eggs')])
    def test_protocol_custom_request_headers_list(self):
        req_headers = self.loop.run_until_complete(self.client.recv())
        self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", req_headers)

    @with_server()
    @with_client('/raw_headers', extra_headers=[('User-Agent', 'Eggs')])
    def test_protocol_custom_request_user_agent(self):
        req_headers = self.loop.run_until_complete(self.client.recv())
        self.loop.run_until_complete(self.client.recv())
        self.assertEqual(req_headers.count("User-Agent"), 1)
        self.assertIn("('User-Agent', 'Eggs')", req_headers)

    @with_server(extra_headers=lambda p, r: {'X-Spam': 'Eggs'})
    @with_client('/raw_headers')
    def test_protocol_custom_response_headers_callable_dict(self):
        self.loop.run_until_complete(self.client.recv())
        resp_headers = self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", resp_headers)

    @with_server(extra_headers=lambda p, r: [('X-Spam', 'Eggs')])
    @with_client('/raw_headers')
    def test_protocol_custom_response_headers_callable_list(self):
        self.loop.run_until_complete(self.client.recv())
        resp_headers = self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", resp_headers)

    @with_server(extra_headers={'X-Spam': 'Eggs'})
    @with_client('/raw_headers')
    def test_protocol_custom_response_headers_dict(self):
        self.loop.run_until_complete(self.client.recv())
        resp_headers = self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", resp_headers)

    @with_server(extra_headers=[('X-Spam', 'Eggs')])
    @with_client('/raw_headers')
    def test_protocol_custom_response_headers_list(self):
        self.loop.run_until_complete(self.client.recv())
        resp_headers = self.loop.run_until_complete(self.client.recv())
        self.assertIn("('X-Spam', 'Eggs')", resp_headers)

    @with_server(extra_headers=[('Server', 'Eggs')])
    @with_client('/raw_headers')
    def test_protocol_custom_response_user_agent(self):
        self.loop.run_until_complete(self.client.recv())
        resp_headers = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(resp_headers.count("Server"), 1)
        self.assertIn("('Server', 'Eggs')", resp_headers)

    @with_server(create_protocol=HealthCheckServerProtocol)
    @with_client()
    def test_custom_protocol_http_request(self):
        # One URL returns an HTTP response.

        # Set url to 'https?://<host>:<port>/__health__/'.
        url = get_server_uri(
            self.server, resource_name='/__health__/', secure=self.secure)
        url = url.replace('ws', 'http')

        if self.secure:
            open_health_check = functools.partial(
                urllib.request.urlopen, url, context=self.client_context)
        else:
            open_health_check = functools.partial(
                urllib.request.urlopen, url)

        response = self.loop.run_until_complete(
            self.loop.run_in_executor(None, open_health_check))

        with contextlib.closing(response):
            self.assertEqual(response.code, 200)
            self.assertEqual(response.read(), b'status = green\n')

        # Other URLs create a WebSocket connection.

        self.loop.run_until_complete(self.client.send("Hello!"))
        reply = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(reply, "Hello!")

    def assert_client_raises_code(self, status_code):
        with self.assertRaises(InvalidStatusCode) as raised:
            self.start_client()
        self.assertEqual(raised.exception.status_code, status_code)

    @with_server(create_protocol=UnauthorizedServerProtocol)
    def test_server_create_protocol(self):
        self.assert_client_raises_code(401)

    @with_server(create_protocol=(lambda *args, **kwargs:
                 UnauthorizedServerProtocol(*args, **kwargs)))
    def test_server_create_protocol_function(self):
        self.assert_client_raises_code(401)

    @with_server(klass=UnauthorizedServerProtocol)
    def test_server_klass(self):
        self.assert_client_raises_code(401)

    @with_server(create_protocol=ForbiddenServerProtocol,
                 klass=UnauthorizedServerProtocol)
    def test_server_create_protocol_over_klass(self):
        self.assert_client_raises_code(403)

    @with_server()
    @with_client('/path', create_protocol=FooClientProtocol)
    def test_client_create_protocol(self):
        self.assertIsInstance(self.client, FooClientProtocol)

    @with_server()
    @with_client('/path', create_protocol=(
                 lambda *args, **kwargs: FooClientProtocol(*args, **kwargs)))
    def test_client_create_protocol_function(self):
        self.assertIsInstance(self.client, FooClientProtocol)

    @with_server()
    @with_client('/path', klass=FooClientProtocol)
    def test_client_klass(self):
        self.assertIsInstance(self.client, FooClientProtocol)

    @with_server()
    @with_client('/path', create_protocol=BarClientProtocol,
                 klass=FooClientProtocol)
    def test_client_create_protocol_over_klass(self):
        self.assertIsInstance(self.client, BarClientProtocol)

    @with_server()
    @with_client('/extensions')
    def test_no_extension(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([]))
        self.assertEqual(repr(self.client.extensions), repr([]))

    @with_server(extensions=[ServerNoOpExtensionFactory()])
    @with_client('/extensions', extensions=[ClientNoOpExtensionFactory()])
    def test_extension(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([NoOpExtension()]))
        self.assertEqual(repr(self.client.extensions), repr([NoOpExtension()]))

    @with_server()
    @with_client('/extensions', extensions=[ClientNoOpExtensionFactory()])
    def test_extension_not_accepted(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([]))
        self.assertEqual(repr(self.client.extensions), repr([]))

    @with_server(extensions=[ServerNoOpExtensionFactory()])
    @with_client('/extensions')
    def test_extension_not_requested(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([]))
        self.assertEqual(repr(self.client.extensions), repr([]))

    @with_server(extensions=[ServerNoOpExtensionFactory([('foo', None)])])
    def test_extension_client_rejection(self):
        with self.assertRaises(NegotiationError):
            self.start_client(
                '/extensions',
                extensions=[ClientNoOpExtensionFactory()],
            )

    @with_server(
        extensions=[
            # No match because the client doesn't send client_max_window_bits.
            ServerPerMessageDeflateFactory(client_max_window_bits=10),
            ServerPerMessageDeflateFactory(),
        ],
    )
    @with_client(
        '/extensions',
        extensions=[
            ClientPerMessageDeflateFactory(),
        ],
    )
    def test_extension_no_match_then_match(self):
        # The order requested by the client has priority.
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([
            PerMessageDeflate(False, False, 15, 15),
        ]))
        self.assertEqual(repr(self.client.extensions), repr([
            PerMessageDeflate(False, False, 15, 15),
        ]))

    @with_server(extensions=[ServerPerMessageDeflateFactory()])
    @with_client('/extensions', extensions=[ClientNoOpExtensionFactory()])
    def test_extension_mismatch(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([]))
        self.assertEqual(repr(self.client.extensions), repr([]))

    @with_server(
        extensions=[
            ServerNoOpExtensionFactory(),
            ServerPerMessageDeflateFactory(),
        ],
    )
    @with_client(
        '/extensions',
        extensions=[
            ClientPerMessageDeflateFactory(),
            ClientNoOpExtensionFactory(),
        ],
    )
    def test_extension_order(self):
        # The order requested by the client has priority.
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([
            PerMessageDeflate(False, False, 15, 15),
            NoOpExtension(),
        ]))
        self.assertEqual(repr(self.client.extensions), repr([
            PerMessageDeflate(False, False, 15, 15),
            NoOpExtension(),
        ]))

    @with_server(extensions=[ServerNoOpExtensionFactory()])
    @unittest.mock.patch.object(WebSocketServerProtocol, 'process_extensions')
    def test_extensions_error(self, _process_extensions):
        _process_extensions.return_value = 'x-no-op', [NoOpExtension()]

        with self.assertRaises(NegotiationError):
            self.start_client(
                '/extensions',
                extensions=[ClientPerMessageDeflateFactory()],
            )

    @with_server(extensions=[ServerNoOpExtensionFactory()])
    @unittest.mock.patch.object(WebSocketServerProtocol, 'process_extensions')
    def test_extensions_error_no_extensions(self, _process_extensions):
        _process_extensions.return_value = 'x-no-op', [NoOpExtension()]

        with self.assertRaises(InvalidHandshake):
            self.start_client('/extensions')

    @with_server(compression='deflate')
    @with_client('/extensions', compression='deflate')
    def test_compression_deflate(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([
            PerMessageDeflate(False, False, 15, 15),
        ]))
        self.assertEqual(repr(self.client.extensions), repr([
            PerMessageDeflate(False, False, 15, 15),
        ]))

    @with_server(
        extensions=[
            ServerPerMessageDeflateFactory(
                client_no_context_takeover=True,
                server_max_window_bits=10,
            ),
        ],
        compression='deflate',  # overridden by explicit config
    )
    @with_client(
        '/extensions',
        extensions=[
            ClientPerMessageDeflateFactory(
                server_no_context_takeover=True,
                client_max_window_bits=12,
            ),
        ],
        compression='deflate',  # overridden by explicit config
    )
    def test_compression_deflate_and_explicit_config(self):
        server_extensions = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_extensions, repr([
            PerMessageDeflate(True, True, 12, 10),
        ]))
        self.assertEqual(repr(self.client.extensions), repr([
            PerMessageDeflate(True, True, 10, 12),
        ]))

    def test_compression_unsupported_server(self):
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(self.start_server(compression='xz'))

    @with_server()
    def test_compression_unsupported_client(self):
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(self.start_client(compression='xz'))

    @with_server()
    @with_client('/subprotocol')
    def test_no_subprotocol(self):
        server_subprotocol = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_subprotocol, repr(None))
        self.assertEqual(self.client.subprotocol, None)

    @with_server(subprotocols=['superchat', 'chat'])
    @with_client('/subprotocol', subprotocols=['otherchat', 'chat'])
    def test_subprotocol(self):
        server_subprotocol = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_subprotocol, repr('chat'))
        self.assertEqual(self.client.subprotocol, 'chat')

    @with_server(subprotocols=['superchat'])
    @with_client('/subprotocol', subprotocols=['otherchat'])
    def test_subprotocol_not_accepted(self):
        server_subprotocol = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_subprotocol, repr(None))
        self.assertEqual(self.client.subprotocol, None)

    @with_server()
    @with_client('/subprotocol', subprotocols=['otherchat', 'chat'])
    def test_subprotocol_not_offered(self):
        server_subprotocol = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_subprotocol, repr(None))
        self.assertEqual(self.client.subprotocol, None)

    @with_server(subprotocols=['superchat', 'chat'])
    @with_client('/subprotocol')
    def test_subprotocol_not_requested(self):
        server_subprotocol = self.loop.run_until_complete(self.client.recv())
        self.assertEqual(server_subprotocol, repr(None))
        self.assertEqual(self.client.subprotocol, None)

    @with_server(subprotocols=['superchat'])
    @unittest.mock.patch.object(WebSocketServerProtocol, 'process_subprotocol')
    def test_subprotocol_error(self, _process_subprotocol):
        _process_subprotocol.return_value = 'superchat'

        with self.assertRaises(NegotiationError):
            self.start_client('/subprotocol', subprotocols=['otherchat'])
        self.run_loop_once()

    @with_server(subprotocols=['superchat'])
    @unittest.mock.patch.object(WebSocketServerProtocol, 'process_subprotocol')
    def test_subprotocol_error_no_subprotocols(self, _process_subprotocol):
        _process_subprotocol.return_value = 'superchat'

        with self.assertRaises(InvalidHandshake):
            self.start_client('/subprotocol')
        self.run_loop_once()

    @with_server(subprotocols=['superchat', 'chat'])
    @unittest.mock.patch.object(WebSocketServerProtocol, 'process_subprotocol')
    def test_subprotocol_error_two_subprotocols(self, _process_subprotocol):
        _process_subprotocol.return_value = 'superchat, chat'

        with self.assertRaises(InvalidHandshake):
            self.start_client(
                '/subprotocol', subprotocols=['superchat', 'chat'])
        self.run_loop_once()

    @with_server()
    @unittest.mock.patch('websockets.server.read_request')
    def test_server_receives_malformed_request(self, _read_request):
        _read_request.side_effect = ValueError("read_request failed")

        with self.assertRaises(InvalidHandshake):
            self.start_client()

    @with_server()
    @unittest.mock.patch('websockets.client.read_response')
    def test_client_receives_malformed_response(self, _read_response):
        _read_response.side_effect = ValueError("read_response failed")

        with self.assertRaises(InvalidHandshake):
            self.start_client()
        self.run_loop_once()

    @with_server()
    @unittest.mock.patch('websockets.client.build_request')
    def test_client_sends_invalid_handshake_request(self, _build_request):
        def wrong_build_request(set_header):
            return '42'
        _build_request.side_effect = wrong_build_request

        with self.assertRaises(InvalidHandshake):
            self.start_client()

    @with_server()
    @unittest.mock.patch('websockets.server.build_response')
    def test_server_sends_invalid_handshake_response(self, _build_response):
        def wrong_build_response(set_header, key):
            return build_response(set_header, '42')
        _build_response.side_effect = wrong_build_response

        with self.assertRaises(InvalidHandshake):
            self.start_client()

    @with_server()
    @unittest.mock.patch('websockets.client.read_response')
    def test_server_does_not_switch_protocols(self, _read_response):
        @asyncio.coroutine
        def wrong_read_response(stream):
            status_code, headers = yield from read_response(stream)
            return 400, headers
        _read_response.side_effect = wrong_read_response

        with self.assertRaises(InvalidStatusCode):
            self.start_client()
        self.run_loop_once()

    @with_server()
    @unittest.mock.patch(
        'websockets.server.WebSocketServerProtocol.process_request')
    def test_server_error_in_handshake(self, _process_request):
        _process_request.side_effect = Exception("process_request crashed")

        with self.assertRaises(InvalidHandshake):
            self.start_client()

    @with_server()
    @unittest.mock.patch('websockets.server.WebSocketServerProtocol.send')
    def test_server_handler_crashes(self, send):
        send.side_effect = ValueError("send failed")

        with self.temp_client():
            self.loop.run_until_complete(self.client.send("Hello!"))
            with self.assertRaises(ConnectionClosed):
                self.loop.run_until_complete(self.client.recv())

        # Connection ends with an unexpected error.
        self.assertEqual(self.client.close_code, 1011)

    @with_server()
    @unittest.mock.patch('websockets.server.WebSocketServerProtocol.close')
    def test_server_close_crashes(self, close):
        close.side_effect = ValueError("close failed")

        with self.temp_client():
            self.loop.run_until_complete(self.client.send("Hello!"))
            reply = self.loop.run_until_complete(self.client.recv())
            self.assertEqual(reply, "Hello!")

        # Connection ends with an abnormal closure.
        self.assertEqual(self.client.close_code, 1006)

    @with_server()
    @with_client()
    @unittest.mock.patch.object(WebSocketClientProtocol, 'handshake')
    def test_client_closes_connection_before_handshake(self, handshake):
        # We have mocked the handshake() method to prevent the client from
        # performing the opening handshake. Force it to close the connection.
        self.client.writer.close()
        # The server should stop properly anyway. It used to hang because the
        # task handling the connection was waiting for the opening handshake.

    @with_server()
    @unittest.mock.patch('websockets.server.read_request')
    def test_server_shuts_down_during_opening_handshake(self, _read_request):
        _read_request.side_effect = asyncio.CancelledError

        self.server.closing = True
        with self.assertRaises(InvalidHandshake) as raised:
            self.start_client()

        # Opening handshake fails with 503 Service Unavailable
        self.assertEqual(str(raised.exception), "Status code not 101: 503")

    @with_server()
    def test_server_shuts_down_during_connection_handling(self):
        with self.temp_client():
            self.server.close()
            with self.assertRaises(ConnectionClosed):
                self.loop.run_until_complete(self.client.recv())

        # Websocket connection terminates with 1001 Going Away.
        self.assertEqual(self.client.close_code, 1001)

    @with_server()
    @unittest.mock.patch('websockets.server.WebSocketServerProtocol.close')
    def test_server_shuts_down_during_connection_close(self, _close):
        _close.side_effect = asyncio.CancelledError

        self.server.closing = True
        with self.temp_client():
            self.loop.run_until_complete(self.client.send("Hello!"))
            reply = self.loop.run_until_complete(self.client.recv())
            self.assertEqual(reply, "Hello!")

        # Websocket connection terminates abnormally.
        self.assertEqual(self.client.close_code, 1006)

    @with_server(create_protocol=ForbiddenServerProtocol)
    def test_invalid_status_error_during_client_connect(self):
        with self.assertRaises(InvalidStatusCode) as raised:
            self.start_client()
        exception = raised.exception
        self.assertEqual(str(exception), "Status code not 101: 403")
        self.assertEqual(exception.status_code, 403)

    @with_server()
    @unittest.mock.patch(
        'websockets.server.WebSocketServerProtocol.write_http_response')
    @unittest.mock.patch(
        'websockets.server.WebSocketServerProtocol.read_http_request')
    def test_connection_error_during_opening_handshake(
            self, _read_http_request, _write_http_response):
        _read_http_request.side_effect = ConnectionError

        # This exception is currently platform-dependent. It was observed to
        # be ConnectionResetError on Linux in the non-SSL case, and
        # InvalidMessage otherwise (including both Linux and macOS). This
        # doesn't matter though since this test is primarily for testing a
        # code path on the server side.
        with self.assertRaises(Exception):
            self.start_client()

        # No response must not be written if the network connection is broken.
        _write_http_response.assert_not_called()

    @with_server()
    @unittest.mock.patch('websockets.server.WebSocketServerProtocol.close')
    def test_connection_error_during_closing_handshake(self, close):
        close.side_effect = ConnectionError

        with self.temp_client():
            self.loop.run_until_complete(self.client.send("Hello!"))
            reply = self.loop.run_until_complete(self.client.recv())
            self.assertEqual(reply, "Hello!")

        # Connection ends with an abnormal closure.
        self.assertEqual(self.client.close_code, 1006)


@unittest.skipUnless(os.path.exists(testcert), "test certificate is missing")
class SSLClientServerTests(ClientServerTests):

    secure = True

    @property
    def server_context(self):
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLSv1)
        ssl_context.load_cert_chain(testcert)
        return ssl_context

    @property
    def client_context(self):
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLSv1)
        ssl_context.load_verify_locations(testcert)
        ssl_context.verify_mode = ssl.CERT_REQUIRED
        return ssl_context

    def start_server(self, **kwds):
        kwds.setdefault('ssl', self.server_context)
        super().start_server(**kwds)

    def start_client(self, path='/', **kwds):
        kwds.setdefault('ssl', self.client_context)
        super().start_client(path, **kwds)

    # TLS over Unix sockets doesn't make sense.
    test_unix_socket = None

    @with_server()
    def test_ws_uri_is_rejected(self):
        with self.assertRaises(ValueError):
            client = connect(
                get_server_uri(self.server, secure=False),
                ssl=self.client_context,
            )
            # With Python ≥ 3.5, the exception is raised by connect() even
            # before awaiting.  However, with Python 3.4 the exception is
            # raised only when awaiting.
            self.loop.run_until_complete(client)          # pragma: no cover


class ClientServerOriginTests(unittest.TestCase):

    def setUp(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

    def tearDown(self):
        self.loop.close()

    def test_checking_origin_succeeds(self):
        server = self.loop.run_until_complete(
            serve(handler, 'localhost', 0, origins=['http://localhost']))
        client = self.loop.run_until_complete(
            connect(get_server_uri(server), origin='http://localhost'))

        self.loop.run_until_complete(client.send("Hello!"))
        self.assertEqual(self.loop.run_until_complete(client.recv()), "Hello!")

        self.loop.run_until_complete(client.close())
        server.close()
        self.loop.run_until_complete(server.wait_closed())

    def test_checking_origin_fails(self):
        server = self.loop.run_until_complete(
            serve(handler, 'localhost', 0, origins=['http://localhost']))
        with self.assertRaisesRegex(InvalidHandshake,
                                    "Status code not 101: 403"):
            self.loop.run_until_complete(
                connect(get_server_uri(server), origin='http://otherhost'))

        server.close()
        self.loop.run_until_complete(server.wait_closed())

    def test_checking_lack_of_origin_succeeds(self):
        server = self.loop.run_until_complete(
            serve(handler, 'localhost', 0, origins=['']))
        client = self.loop.run_until_complete(connect(get_server_uri(server)))

        self.loop.run_until_complete(client.send("Hello!"))
        self.assertEqual(self.loop.run_until_complete(client.recv()), "Hello!")

        self.loop.run_until_complete(client.close())
        server.close()
        self.loop.run_until_complete(server.wait_closed())


try:
    from .py35._test_client_server import ContextManagerTests           # noqa
except (SyntaxError, ImportError):                          # pragma: no cover
    pass


try:
    from .py36._test_client_server import AsyncIteratorTests            # noqa
except (SyntaxError, ImportError):                          # pragma: no cover
    pass
