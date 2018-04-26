"""
The :mod:`websockets.handshake` module deals with the WebSocket opening
handshake according to `section 4 of RFC 6455`_.

.. _section 4 of RFC 6455: http://tools.ietf.org/html/rfc6455#section-4

It provides functions to implement the handshake with any existing HTTP
library. You must pass to these functions:

- A ``set_header`` function accepting a header name and a header value,
- A ``get_header`` function accepting a header name and returning the header
  value.

The inputs and outputs of ``get_header`` and ``set_header`` are :class:`str`
objects containing only ASCII characters.

Some checks cannot be performed because they depend too much on the
context; instead, they're documented below.

To accept a connection, a server must:

- Read the request, check that the method is GET, and check the headers with
  :func:`check_request`,
- Send a 101 response to the client with the headers created by
  :func:`build_response` if the request is valid; otherwise, send an
  appropriate HTTP error code.

To open a connection, a client must:

- Send a GET request to the server with the headers created by
  :func:`build_request`,
- Read the response, check that the status code is 101, and check the headers
  with :func:`check_response`.

"""

import base64
import hashlib
import random

from .exceptions import InvalidHandshake


__all__ = [
    'build_request', 'check_request',
    'build_response', 'check_response',
]

GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'


def build_request(set_header):
    """
    Build a handshake request to send to the server.

    Return the ``key`` which must be passed to :func:`check_response`.

    """
    rand = bytes(random.getrandbits(8) for _ in range(16))
    key = base64.b64encode(rand).decode()
    set_header('Upgrade', 'websocket')
    set_header('Connection', 'Upgrade')
    set_header('Sec-WebSocket-Key', key)
    set_header('Sec-WebSocket-Version', '13')
    return key


def check_request(get_header):
    """
    Check a handshake request received from the client.

    If the handshake is valid, this function returns the ``key`` which must be
    passed to :func:`build_response`.

    Otherwise it raises an :exc:`~websockets.exceptions.InvalidHandshake`
    exception and the server must return an error like 400 Bad Request.

    This function doesn't verify that the request is an HTTP/1.1 or higher GET
    request and doesn't perform Host and Origin checks. These controls are
    usually performed earlier in the HTTP request handling code. They're the
    responsibility of the caller.

    """
    try:
        assert get_header('Upgrade').lower() == 'websocket'
        assert any(
            token.strip() == 'upgrade'
            for token in get_header('Connection').lower().split(','))
        key = get_header('Sec-WebSocket-Key')
        assert len(base64.b64decode(key.encode(), validate=True)) == 16
        assert get_header('Sec-WebSocket-Version') == '13'
    except Exception as exc:
        raise InvalidHandshake("Invalid request") from exc
    else:
        return key


def build_response(set_header, key):
    """
    Build a handshake response to send to the client.

    ``key`` comes from :func:`check_request`.

    """
    set_header('Upgrade', 'websocket')
    set_header('Connection', 'Upgrade')
    set_header('Sec-WebSocket-Accept', accept(key))


def check_response(get_header, key):
    """
    Check a handshake response received from the server.

    ``key`` comes from :func:`build_request`.

    If the handshake is valid, this function returns ``None``.

    Otherwise it raises an :exc:`~websockets.exceptions.InvalidHandshake`
    exception.

    This function doesn't verify that the response is an HTTP/1.1 or higher
    response with a 101 status code. These controls are the responsibility of
    the caller.

    """
    try:
        assert get_header('Upgrade').lower() == 'websocket'
        assert any(
            token.strip() == 'upgrade'
            for token in get_header('Connection').lower().split(','))
        assert get_header('Sec-WebSocket-Accept') == accept(key)
    except Exception as exc:
        raise InvalidHandshake("Invalid response") from exc


def accept(key):
    sha1 = hashlib.sha1((key + GUID).encode()).digest()
    return base64.b64encode(sha1).decode()
