import asyncio
import unittest

from .http import *
from .http import build_headers, read_headers


class HTTPAsyncTests(unittest.TestCase):

    def setUp(self):
        super().setUp()
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.stream = asyncio.StreamReader(loop=self.loop)

    def tearDown(self):
        self.loop.close()
        super().tearDown()

    def test_read_request(self):
        # Example from the protocol overview in RFC 6455
        self.stream.feed_data(
            b'GET /chat HTTP/1.1\r\n'
            b'Host: server.example.com\r\n'
            b'Upgrade: websocket\r\n'
            b'Connection: Upgrade\r\n'
            b'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
            b'Origin: http://example.com\r\n'
            b'Sec-WebSocket-Protocol: chat, superchat\r\n'
            b'Sec-WebSocket-Version: 13\r\n'
            b'\r\n'
        )
        path, headers = self.loop.run_until_complete(
            read_request(self.stream))
        self.assertEqual(path, '/chat')
        self.assertEqual(dict(headers)['Upgrade'], 'websocket')

    def test_read_response(self):
        # Example from the protocol overview in RFC 6455
        self.stream.feed_data(
            b'HTTP/1.1 101 Switching Protocols\r\n'
            b'Upgrade: websocket\r\n'
            b'Connection: Upgrade\r\n'
            b'Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n'
            b'Sec-WebSocket-Protocol: chat\r\n'
            b'\r\n'
        )
        status_code, headers = self.loop.run_until_complete(
            read_response(self.stream))
        self.assertEqual(status_code, 101)
        self.assertEqual(dict(headers)['Upgrade'], 'websocket')

    def test_request_method(self):
        self.stream.feed_data(b'OPTIONS * HTTP/1.1\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_request(self.stream))

    def test_request_version(self):
        self.stream.feed_data(b'GET /chat HTTP/1.0\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_request(self.stream))

    def test_response_version(self):
        self.stream.feed_data(b'HTTP/1.0 400 Bad Request\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_response(self.stream))

    def test_response_status(self):
        self.stream.feed_data(b'HTTP/1.1 007 My name is Bond\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_response(self.stream))

    def test_response_reason(self):
        self.stream.feed_data(b'HTTP/1.1 200 \x7f\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_response(self.stream))

    def test_header_name(self):
        self.stream.feed_data(b'foo bar: baz qux\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_headers(self.stream))

    def test_header_value(self):
        self.stream.feed_data(b'foo: \x00\x00\x0f\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_headers(self.stream))

    def test_headers_limit(self):
        self.stream.feed_data(b'foo: bar\r\n' * 257 + b'\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_headers(self.stream))

    def test_line_limit(self):
        # Header line contains 5 + 4090 + 2 = 4097 bytes.
        self.stream.feed_data(b'foo: ' + b'a' * 4090 + b'\r\n\r\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_headers(self.stream))

    def test_line_ending(self):
        self.stream.feed_data(b'foo: bar\n\n')
        with self.assertRaises(ValueError):
            self.loop.run_until_complete(read_headers(self.stream))


class HTTPSyncTests(unittest.TestCase):

    def test_build_headers(self):
        headers = build_headers([
            ('X-Foo', 'Bar'),
            ('X-Baz', 'Quux Quux'),
        ])

        self.assertEqual(headers['X-Foo'], 'Bar')
        self.assertEqual(headers['X-Bar'], None)

        self.assertEqual(headers.get('X-Bar', ''), '')
        self.assertEqual(headers.get('X-Baz', ''), 'Quux Quux')

    def test_build_headers_multi_value(self):
        headers = build_headers([
            ('X-Foo', 'Bar'),
            ('X-Foo', 'Baz'),
        ])

        # Getting a single value is non-deterministic.
        self.assertIn(headers['X-Foo'], ['Bar', 'Baz'])
        self.assertIn(headers.get('X-Foo'), ['Bar', 'Baz'])

        # Ordering is deterministic when getting all values.
        self.assertEqual(headers.get_all('X-Foo'), ['Bar', 'Baz'])
