"""
The :mod:`websockets.http` module provides basic HTTP parsing and
serialization. It is merely adequate for WebSocket handshake messages.

Its functions cannot be imported from :mod:`websockets`. They must be imported
from :mod:`websockets.http`.

"""

import asyncio
import http.client
import re
import sys

from .version import version as websockets_version


__all__ = ['read_request', 'read_response', 'USER_AGENT']

MAX_HEADERS = 256
MAX_LINE = 4096

USER_AGENT = ' '.join((
    'Python/{}'.format(sys.version[:3]),
    'websockets/{}'.format(websockets_version),
))


# See https://tools.ietf.org/html/rfc7230#appendix-B.

# Regex for validating header names.

_token_re = re.compile(rb'[-!#$%&\'*+.^_`|~0-9a-zA-Z]+')

# Regex for validating header values.

# We don't attempt to support obsolete line folding.

# Include HTAB (\x09), SP (\x20), VCHAR (\x21-\x7e), obs-text (\x80-\xff).

# The ABNF is complicated because it attempts to express that optional
# whitespace is ignored. We strip whitespace and don't revalidate that.

# See also https://www.rfc-editor.org/errata_search.php?rfc=7230&eid=4189

_value_re = re.compile(rb'[\x09\x20-\x7e\x80-\xff]*')


@asyncio.coroutine
def read_request(stream):
    """
    Read an HTTP/1.1 GET request from ``stream``.

    ``stream`` is an :class:`~asyncio.StreamReader`.

    Return ``(path, headers)`` where ``path`` is a :class:`str` and
    ``headers`` is a list of ``(name, value)`` tuples.

    ``path`` isn't URL-decoded or validated in any way.

    Non-ASCII characters are represented with surrogate escapes.

    Raise an exception if the request isn't well formatted.

    Don't attempt to read the request body because WebSocket handshake
    requests don't have one. If the request contains a body, it may be
    read from ``stream`` after this coroutine returns.

    """
    # https://tools.ietf.org/html/rfc7230#section-3.1.1

    # Parsing is simple because fixed values are expected for method and
    # version and because path isn't checked. Since WebSocket software tends
    # to implement HTTP/1.1 strictly, there's little need for lenient parsing.

    # Given the implementation of read_line(), request_line ends with CRLF.
    request_line = yield from read_line(stream)

    # This may raise "ValueError: not enough values to unpack"
    method, path, version = request_line[:-2].split(b' ', 2)

    if method != b'GET':
        raise ValueError("Unsupported HTTP method: %r" % method)
    if version != b'HTTP/1.1':
        raise ValueError("Unsupported HTTP version: %r" % version)

    path = path.decode('ascii', 'surrogateescape')

    headers = yield from read_headers(stream)

    return path, headers


@asyncio.coroutine
def read_response(stream):
    """
    Read an HTTP/1.1 response from ``stream``.

    ``stream`` is an :class:`~asyncio.StreamReader`.

    Return ``(status_code, headers)`` where ``status_code`` is a :class:`int`
    and ``headers`` is a list of ``(name, value)`` tuples.

    Non-ASCII characters are represented with surrogate escapes.

    Raise an exception if the response isn't well formatted.

    Don't attempt to read the response body, because WebSocket handshake
    responses don't have one. If the response contains a body, it may be
    read from ``stream`` after this coroutine returns.

    """
    # https://tools.ietf.org/html/rfc7230#section-3.1.2

    # As in read_request, parsing is simple because a fixed value is expected
    # for version, status_code is a 3-digit number, and reason can be ignored.

    # Given the implementation of read_line(), status_line ends with CRLF.
    status_line = yield from read_line(stream)

    # This may raise "ValueError: not enough values to unpack"
    version, status_code, reason = status_line[:-2].split(b' ', 2)

    if version != b'HTTP/1.1':
        raise ValueError("Unsupported HTTP version: %r" % version)
    # This may raise "ValueError: invalid literal for int() with base 10"
    status_code = int(status_code)
    if not 100 <= status_code < 1000:
        raise ValueError("Unsupported HTTP status_code code: %d" % status_code)
    if not _value_re.fullmatch(reason):
        raise ValueError("Invalid HTTP reason phrase: %r" % reason)

    headers = yield from read_headers(stream)

    return status_code, headers


@asyncio.coroutine
def read_headers(stream):
    """
    Read HTTP headers from ``stream``.

    ``stream`` is an :class:`~asyncio.StreamReader`.

    Return ``(start_line, headers)`` where ``start_line`` is :class:`bytes`
    and ``headers`` is a list of ``(name, value)`` tuples.

    Non-ASCII characters are represented with surrogate escapes.

    """
    # https://tools.ietf.org/html/rfc7230#section-3.2

    # We don't attempt to support obsolete line folding.

    headers = []
    for _ in range(MAX_HEADERS + 1):
        line = yield from read_line(stream)
        if line == b'\r\n':
            break

        # This may raise "ValueError: not enough values to unpack"
        name, value = line[:-2].split(b':', 1)
        if not _token_re.fullmatch(name):
            raise ValueError("Invalid HTTP header name: %r" % name)
        value = value.strip(b' \t')
        if not _value_re.fullmatch(value):
            raise ValueError("Invalid HTTP header value: %r" % value)

        headers.append((
            name.decode('ascii'),   # guaranteed to be ASCII at this point
            value.decode('ascii', 'surrogateescape'),
        ))

    else:
        raise ValueError("Too many HTTP headers")

    return headers


@asyncio.coroutine
def read_line(stream):
    """
    Read a single line from ``stream``.

    ``stream`` is an :class:`~asyncio.StreamReader`.

    """
    # Security: this is bounded by the StreamReader's limit (default = 32kB).
    line = yield from stream.readline()
    # Security: this guarantees header values are small (hardcoded = 4kB)
    if len(line) > MAX_LINE:
        raise ValueError("Line too long")
    # Not mandatory but safe - https://tools.ietf.org/html/rfc7230#section-3.5
    if not line.endswith(b'\r\n'):
        raise ValueError("Line without CRLF")
    return line


def build_headers(raw_headers):
    """
    Build a date structure for HTTP headers from a list of name - value pairs.

    See also https://github.com/aaugustin/websockets/issues/210.

    """
    headers = http.client.HTTPMessage()
    headers._headers = raw_headers  # HACK
    return headers
