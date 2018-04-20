import contextlib
import unittest

from .exceptions import InvalidHandshake
from .handshake import *
from .handshake import accept  # private API


class HandshakeTests(unittest.TestCase):

    def test_accept(self):
        # Test vector from RFC 6455
        key = "dGhlIHNhbXBsZSBub25jZQ=="
        acc = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        self.assertEqual(accept(key), acc)

    def test_round_trip(self):
        request_headers = {}
        request_key = build_request(request_headers.__setitem__)
        response_key = check_request(request_headers.__getitem__)
        self.assertEqual(request_key, response_key)
        response_headers = {}
        build_response(response_headers.__setitem__, response_key)
        check_response(response_headers.__getitem__, request_key)

    @contextlib.contextmanager
    def assertInvalidRequestHeaders(self):
        """
        Provide request headers for corruption.

        Assert that the transformation made them invalid.

        """
        headers = {}
        build_request(headers.__setitem__)
        yield headers
        with self.assertRaises(InvalidHandshake):
            check_request(headers.__getitem__)

    def test_request_invalid_upgrade(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Upgrade'] = 'socketweb'

    def test_request_missing_upgrade(self):
        with self.assertInvalidRequestHeaders() as headers:
            del headers['Upgrade']

    def test_request_invalid_connection(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Connection'] = 'Downgrade'

    def test_request_missing_connection(self):
        with self.assertInvalidRequestHeaders() as headers:
            del headers['Connection']

    def test_request_invalid_key_not_base64(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Sec-WebSocket-Key'] = "!@#$%^&*()"

    def test_request_invalid_key_not_well_padded(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Sec-WebSocket-Key'] = "CSIRmL8dWYxeAdr/XpEHRw"

    def test_request_invalid_key_not_16_bytes_long(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Sec-WebSocket-Key'] = "ZLpprpvK4PE="

    def test_request_missing_key(self):
        with self.assertInvalidRequestHeaders() as headers:
            del headers['Sec-WebSocket-Key']

    def test_request_invalid_version(self):
        with self.assertInvalidRequestHeaders() as headers:
            headers['Sec-WebSocket-Version'] = '42'

    def test_request_missing_version(self):
        with self.assertInvalidRequestHeaders() as headers:
            del headers['Sec-WebSocket-Version']

    @contextlib.contextmanager
    def assertInvalidResponseHeaders(self, key='CSIRmL8dWYxeAdr/XpEHRw=='):
        """
        Provide response headers for corruption.

        Assert that the transformation made them invalid.

        """
        headers = {}
        build_response(headers.__setitem__, key)
        yield headers
        with self.assertRaises(InvalidHandshake):
            check_response(headers.__getitem__, key)

    def test_response_invalid_upgrade(self):
        with self.assertInvalidResponseHeaders() as headers:
            headers['Upgrade'] = 'socketweb'

    def test_response_missing_upgrade(self):
        with self.assertInvalidResponseHeaders() as headers:
            del headers['Upgrade']

    def test_response_invalid_connection(self):
        with self.assertInvalidResponseHeaders() as headers:
            headers['Connection'] = 'Downgrade'

    def test_response_missing_connection(self):
        with self.assertInvalidResponseHeaders() as headers:
            del headers['Connection']

    def test_response_invalid_accept(self):
        with self.assertInvalidResponseHeaders() as headers:
            other_key = "1Eq4UDEFQYg3YspNgqxv5g=="
            headers['Sec-WebSocket-Accept'] = accept(other_key)

    def test_response_missing_accept(self):
        with self.assertInvalidResponseHeaders() as headers:
            del headers['Sec-WebSocket-Accept']
