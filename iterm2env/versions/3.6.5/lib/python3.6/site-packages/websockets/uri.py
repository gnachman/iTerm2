"""
The :mod:`websockets.uri` module implements parsing of WebSocket URIs
according to `section 3 of RFC 6455`_.

.. _section 3 of RFC 6455: http://tools.ietf.org/html/rfc6455#section-3

"""

import collections
import urllib.parse

from .exceptions import InvalidURI


__all__ = ['parse_uri', 'WebSocketURI']

WebSocketURI = collections.namedtuple(
    'WebSocketURI', ['secure', 'host', 'port', 'resource_name'])
WebSocketURI.__doc__ = """WebSocket URI.

* ``secure`` is the secure flag
* ``host`` is the lower-case host
* ``port`` if the integer port, it's always provided even if it's the default
* ``resource_name`` is the resource name, that is, the path and optional query

"""


def parse_uri(uri):
    """
    This function parses and validates a WebSocket URI.

    If the URI is valid, it returns a :class:`WebSocketURI`.

    Otherwise it raises an :exc:`~websockets.exceptions.InvalidURI` exception.

    """
    uri = urllib.parse.urlparse(uri)
    try:
        assert uri.scheme in ['ws', 'wss']
        assert uri.params == ''
        assert uri.fragment == ''
        assert uri.username is None
        assert uri.password is None
        assert uri.hostname is not None
    except AssertionError as exc:
        raise InvalidURI("{} isn't a valid URI".format(uri)) from exc

    secure = uri.scheme == 'wss'
    host = uri.hostname
    port = uri.port or (443 if secure else 80)
    resource_name = uri.path or '/'
    if uri.query:
        resource_name += '?' + uri.query
    return WebSocketURI(secure, host, port, resource_name)
