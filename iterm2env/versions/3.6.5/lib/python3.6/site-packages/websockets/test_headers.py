import unittest

from .exceptions import InvalidHeader
from .headers import *


class HeadersTests(unittest.TestCase):

    def test_parse_extension_list(self):
        for header, parsed in [
            # Synthetic examples
            (
                'foo',
                [('foo', [])],
            ),
            (
                'foo, bar',
                [('foo', []), ('bar', [])],
            ),
            (
                'foo; name; token=token; quoted-string="quoted-string", '
                'bar; quux; quuux',
                [
                    ('foo', [('name', None), ('token', 'token'),
                             ('quoted-string', 'quoted-string')]),
                    ('bar', [('quux', None), ('quuux', None)]),
                ],
            ),
            # Pathological examples
            (
                ',\t, ,  ,foo  ;bar = 42,,   baz,,',
                [('foo', [('bar', '42')]), ('baz', [])],
            ),
            # Realistic use cases for permessage-deflate
            (
                'permessage-deflate',
                [('permessage-deflate', [])],
            ),
            (
                'permessage-deflate; client_max_window_bits',
                [('permessage-deflate', [('client_max_window_bits', None)])],
            ),
            (
                'permessage-deflate; server_max_window_bits=10',
                [('permessage-deflate', [('server_max_window_bits', '10')])],
            ),
        ]:
            with self.subTest(header=header):
                self.assertEqual(parse_extension_list(header), parsed)
                # Also ensure that build_extension_list round-trips cleanly.
                unparsed = build_extension_list(parsed)
                self.assertEqual(parse_extension_list(unparsed), parsed)

    def test_parse_extension_list_invalid_header(self):
        for header in [
            # Truncated examples
            '',
            ',\t,'
            'foo;',
            'foo; bar;',
            'foo; bar=',
            'foo; bar="baz',
            # Wrong delimiter
            'foo, bar, baz=quux; quuux',
            # Value in quoted string parameter that isn't a token
            'foo; bar=" "',
        ]:
            with self.subTest(header=header):
                with self.assertRaises(InvalidHeader):
                    parse_extension_list(header)

    def test_parse_protocol_list(self):
        for header, parsed in [
            # Synthetic examples
            (
                'foo',
                ['foo'],
            ),
            (
                'foo, bar',
                ['foo', 'bar'],
            ),
            # Pathological examples
            (
                ',\t, ,  ,foo  ,,   bar,baz,,',
                ['foo', 'bar', 'baz'],
            ),
        ]:
            with self.subTest(header=header):
                self.assertEqual(parse_protocol_list(header), parsed)
                # Also ensure that build_protocol_list round-trips cleanly.
                unparsed = build_protocol_list(parsed)
                self.assertEqual(parse_protocol_list(unparsed), parsed)

    def test_parse_protocol_list_invalid_header(self):
        for header in [
            # Truncated examples
            '',
            ',\t,'
            # Wrong delimiter
            'foo; bar',
        ]:
            with self.subTest(header=header):
                with self.assertRaises(InvalidHeader):
                    parse_protocol_list(header)
