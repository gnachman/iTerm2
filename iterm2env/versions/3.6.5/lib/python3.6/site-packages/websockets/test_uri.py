import unittest

from .exceptions import InvalidURI
from .uri import *


VALID_URIS = [
    ('ws://localhost/', (False, 'localhost', 80, '/')),
    ('wss://localhost/', (True, 'localhost', 443, '/')),
    ('ws://localhost/path?query', (False, 'localhost', 80, '/path?query')),
    ('WS://LOCALHOST/PATH?QUERY', (False, 'localhost', 80, '/PATH?QUERY')),
]

INVALID_URIS = [
    'http://localhost/',
    'https://localhost/',
    'ws://localhost/path#fragment',
    'ws://user:pass@localhost/',
]


class URITests(unittest.TestCase):

    def test_success(self):
        for uri, parsed in VALID_URIS:
            with self.subTest(uri=uri):
                self.assertEqual(parse_uri(uri), parsed)

    def test_error(self):
        for uri in INVALID_URIS:
            with self.subTest(uri=uri):
                with self.assertRaises(InvalidURI):
                    parse_uri(uri)
