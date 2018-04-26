"""
The :mod:`websockets.server` module defines a simple WebSocket server API.

"""

import asyncio
import collections.abc
import logging
import sys

from .compatibility import (
    BAD_REQUEST, FORBIDDEN, INTERNAL_SERVER_ERROR, SERVICE_UNAVAILABLE,
    SWITCHING_PROTOCOLS, asyncio_ensure_future
)
from .exceptions import (
    AbortHandshake, InvalidHandshake, InvalidMessage, InvalidOrigin,
    NegotiationError
)
from .extensions.permessage_deflate import ServerPerMessageDeflateFactory
from .handshake import build_response, check_request
from .headers import (
    build_extension_list, parse_extension_list, parse_protocol_list
)
from .http import USER_AGENT, build_headers, read_request
from .protocol import WebSocketCommonProtocol


__all__ = ['serve', 'unix_serve', 'WebSocketServerProtocol']

logger = logging.getLogger(__name__)


class WebSocketServerProtocol(WebSocketCommonProtocol):
    """
    Complete WebSocket server implementation as an :class:`asyncio.Protocol`.

    This class inherits most of its methods from
    :class:`~websockets.protocol.WebSocketCommonProtocol`.

    For the sake of simplicity, it doesn't rely on a full HTTP implementation.
    Its support for HTTP responses is very limited.

    """
    is_client = False
    side = 'server'

    def __init__(self, ws_handler, ws_server, *,
                 origins=None, extensions=None, subprotocols=None,
                 extra_headers=None, **kwds):
        self.ws_handler = ws_handler
        self.ws_server = ws_server
        self.origins = origins
        self.available_extensions = extensions
        self.available_subprotocols = subprotocols
        self.extra_headers = extra_headers
        super().__init__(**kwds)

    def connection_made(self, transport):
        """
        Register connection and initialize a task to handle it.

        """
        super().connection_made(transport)
        # Register the connection with the server before creating the handler
        # task. Registering at the beginning of the handler coroutine would
        # create a race condition between the creation of the task, which
        # schedules its execution, and the moment the handler starts running.
        self.ws_server.register(self)
        self.handler_task = asyncio_ensure_future(
            self.handler(), loop=self.loop)

    @asyncio.coroutine
    def handler(self):
        """
        Handle the lifecycle of a WebSocket connection.

        Since this method doesn't have a caller able to handle exceptions, it
        attemps to log relevant ones and close the connection properly.

        """
        try:

            try:
                path = yield from self.handshake(
                    origins=self.origins,
                    available_extensions=self.available_extensions,
                    available_subprotocols=self.available_subprotocols,
                    extra_headers=self.extra_headers,
                )
            except ConnectionError as exc:
                logger.debug(
                    "Connection error in opening handshake", exc_info=True)
                raise
            except Exception as exc:
                if self._is_server_shutting_down(exc):
                    early_response = (
                        SERVICE_UNAVAILABLE,
                        [],
                        b"Server is shutting down.",
                    )
                elif isinstance(exc, AbortHandshake):
                    early_response = (
                        exc.status,
                        exc.headers,
                        exc.body,
                    )
                elif isinstance(exc, InvalidOrigin):
                    logger.warning("Invalid origin", exc_info=True)
                    early_response = (
                        FORBIDDEN,
                        [],
                        str(exc).encode(),
                    )
                elif isinstance(exc, InvalidHandshake):
                    logger.warning("Invalid handshake", exc_info=True)
                    early_response = (
                        BAD_REQUEST,
                        [],
                        str(exc).encode(),
                    )
                else:
                    logger.warning("Error in opening handshake", exc_info=True)
                    early_response = (
                        INTERNAL_SERVER_ERROR,
                        [],
                        b"See server log for more information.",
                    )

                yield from self.write_http_response(*early_response)
                yield from self.close_connection(after_handshake=False)

                return

            try:
                yield from self.ws_handler(self, path)
            except Exception as exc:
                if self._is_server_shutting_down(exc):
                    yield from self.fail_connection(1001)
                else:
                    logger.error("Error in connection handler", exc_info=True)
                    yield from self.fail_connection(1011)
                raise

            try:
                yield from self.close()
            except ConnectionError as exc:
                logger.debug(
                    "Connection error in closing handshake", exc_info=True)
                raise
            except Exception as exc:
                if not self._is_server_shutting_down(exc):
                    logger.warning("Error in closing handshake", exc_info=True)
                raise

        except Exception:
            # Last-ditch attempt to avoid leaking connections on errors.
            try:
                self.writer.close()
            except Exception:                               # pragma: no cover
                pass

        finally:
            # Unregister the connection with the server when the handler task
            # terminates. Registration is tied to the lifecycle of the handler
            # task because the server waits for tasks attached to registered
            # connections before terminating.
            self.ws_server.unregister(self)

    def _is_server_shutting_down(self, exc):
        """
        Decide whether an exception means that the server is shutting down.

        """
        return (
            isinstance(exc, asyncio.CancelledError) and
            self.ws_server.closing
        )

    @asyncio.coroutine
    def read_http_request(self):
        """
        Read request line and headers from the HTTP request.

        Raise :exc:`~websockets.exceptions.InvalidMessage` if the HTTP message
        is malformed or isn't an HTTP/1.1 GET request.

        Don't attempt to read the request body because WebSocket handshake
        requests don't have one. If the request contains a body, it may be
        read from ``self.reader`` after this coroutine returns.

        """
        try:
            path, headers = yield from read_request(self.reader)
        except ValueError as exc:
            raise InvalidMessage("Malformed HTTP message") from exc

        self.path = path
        self.request_headers = build_headers(headers)
        self.raw_request_headers = headers

        return path, self.request_headers

    @asyncio.coroutine
    def write_http_response(self, status, headers, body=None):
        """
        Write status line and headers to the HTTP response.

        This coroutine is also able to write a response body.

        """
        self.response_headers = build_headers(headers)
        self.raw_response_headers = headers

        # Since the status line and headers only contain ASCII characters,
        # we can keep this simple.
        response = [
            'HTTP/1.1 {value} {phrase}'.format(
                value=status.value, phrase=status.phrase)]
        response.extend('{}: {}'.format(k, v) for k, v in headers)
        response.append('\r\n')
        response = '\r\n'.join(response).encode()

        self.writer.write(response)

        if body is not None:
            self.writer.write(body)

    @asyncio.coroutine
    def process_request(self, path, request_headers):
        """
        Intercept the HTTP request and return an HTTP response if needed.

        ``request_headers`` are a :class:`~http.client.HTTPMessage`.

        If this coroutine returns ``None``, the WebSocket handshake continues.
        If it returns a status code, headers and a optionally a response body,
        that HTTP response is sent and the connection is closed.

        The HTTP status must be a :class:`~http.HTTPStatus`. HTTP headers must
        be an iterable of ``(name, value)`` pairs. If provided, the HTTP
        response body must be :class:`bytes`.

        (:class:`~http.HTTPStatus` was added in Python 3.5. Use a compatible
        object on earlier versions. Look at ``SWITCHING_PROTOCOLS`` in
        ``websockets.compatibility`` for an example.)

        This method may be overridden to check the request headers and set a
        different status, for example to authenticate the request and return
        ``HTTPStatus.UNAUTHORIZED`` or ``HTTPStatus.FORBIDDEN``.

        It is declared as a coroutine because such authentication checks are
        likely to require network requests.

        """

    def process_origin(self, get_header, origins=None):
        """
        Handle the Origin HTTP request header.

        Raise :exc:`~websockets.exceptions.InvalidOrigin` if the origin isn't
        acceptable.

        """
        origin = get_header('Origin')
        if origins is not None:
            if origin not in origins:
                raise InvalidOrigin("Origin not allowed: {}".format(origin))
        return origin

    @staticmethod
    def process_extensions(headers, available_extensions):
        """
        Handle the Sec-WebSocket-Extensions HTTP request header.

        Accept or reject each extension proposed in the client request.
        Negotiate parameters for accepted extensions.

        Return the Sec-WebSocket-Extensions HTTP response header and the list
        of accepted extensions.

        Raise :exc:`~websockets.exceptions.InvalidHandshake` to abort the
        handshake with an HTTP 400 error code. (The default implementation
        never does this.)

        :rfc:`6455` leaves the rules up to the specification of each
        :extension.

        To provide this level of flexibility, for each extension proposed by
        the client, we check for a match with each extension available in the
        server configuration. If no match is found, the extension is ignored.

        If several variants of the same extension are proposed by the client,
        it may be accepted severel times, which won't make sense in general.
        Extensions must implement their own requirements. For this purpose,
        the list of previously accepted extensions is provided.

        This process doesn't allow the server to reorder extensions. It can
        only select a subset of the extensions proposed by the client.

        Other requirements, for example related to mandatory extensions or the
        order of extensions, may be implemented by overriding this method.

        """
        response_header = []
        accepted_extensions = []

        header_values = headers.get_all('Sec-WebSocket-Extensions')

        if header_values is not None and available_extensions is not None:

            parsed_header_values = sum([
                parse_extension_list(header_value)
                for header_value in header_values
            ], [])

            for name, request_params in parsed_header_values:

                for extension_factory in available_extensions:

                    # Skip non-matching extensions based on their name.
                    if extension_factory.name != name:
                        continue

                    # Skip non-matching extensions based on their params.
                    try:
                        response_params, extension = (
                            extension_factory.process_request_params(
                                request_params, accepted_extensions))
                    except NegotiationError:
                        continue

                    # Add matching extension to the final list.
                    response_header.append((name, response_params))
                    accepted_extensions.append(extension)

                    # Break out of the loop once we have a match.
                    break

                # If we didn't break from the loop, no extension in our list
                # matched what the client sent. The extension is declined.

        # Serialize extension header.
        if response_header:
            response_header = build_extension_list(response_header)
        else:
            response_header = None

        return response_header, accepted_extensions

    # Not @staticmethod because it calls self.select_subprotocol()
    def process_subprotocol(self, headers, available_subprotocols):
        """
        Handle the Sec-WebSocket-Protocol HTTP request header.

        Return Sec-WebSocket-Protocol HTTP response header, which is the same
        as the selected subprotocol.

        """
        subprotocol = None

        header_values = headers.get_all('Sec-WebSocket-Protocol')

        if header_values is not None and available_subprotocols is not None:

            parsed_header_values = sum([
                parse_protocol_list(header_value)
                for header_value in header_values
            ], [])

            subprotocol = self.select_subprotocol(
                parsed_header_values,
                available_subprotocols,
            )

        return subprotocol

    @staticmethod
    def select_subprotocol(client_subprotocols, server_subprotocols):
        """
        Pick a subprotocol among those offered by the client.

        If several subprotocols are supported by the client and the server,
        the default implementation selects the preferred subprotocols by
        giving equal value to the priorities of the client and the server.

        If no subprotocols are supported by the client and the server, it
        proceeds without a subprotocol.

        This is unlikely to be the most useful implementation in practice, as
        many servers providing a subprotocol will require that the client uses
        that subprotocol. Such rules can be implemented in a subclass.

        """
        subprotocols = set(client_subprotocols) & set(server_subprotocols)
        if not subprotocols:
            return None
        priority = lambda p: (
            client_subprotocols.index(p) + server_subprotocols.index(p))
        return sorted(subprotocols, key=priority)[0]

    @asyncio.coroutine
    def handshake(self, origins=None, available_extensions=None,
                  available_subprotocols=None, extra_headers=None):
        """
        Perform the server side of the opening handshake.

        If provided, ``origins`` is a list of acceptable HTTP Origin values.
        Include ``''`` if the lack of an origin is acceptable.

        If provided, ``available_extensions`` is a list of supported
        extensions in the order in which they should be used.

        If provided, ``available_subprotocols`` is a list of supported
        subprotocols in order of decreasing preference.

        If provided, ``extra_headers`` sets additional HTTP response headers.
        It can be a mapping or an iterable of (name, value) pairs. It can also
        be a callable taking the request path and headers in arguments.

        Raise :exc:`~websockets.exceptions.InvalidHandshake` if the handshake
        fails.

        Return the path of the URI of the request.

        """
        path, request_headers = yield from self.read_http_request()

        # Hook for customizing request handling, for example checking
        # authentication or treating some paths as plain HTTP endpoints.

        early_response = yield from self.process_request(path, request_headers)
        if early_response is not None:
            raise AbortHandshake(*early_response)

        get_header = lambda k: request_headers.get(k, '')

        key = check_request(get_header)

        self.origin = self.process_origin(get_header, origins)

        extensions_header, self.extensions = self.process_extensions(
            request_headers, available_extensions)

        protocol_header = self.subprotocol = self.process_subprotocol(
            request_headers, available_subprotocols)

        response_headers = []
        set_header = lambda k, v: response_headers.append((k, v))
        is_header_set = lambda k: k in dict(response_headers).keys()

        if extensions_header is not None:
            set_header('Sec-WebSocket-Extensions', extensions_header)

        if self.subprotocol is not None:
            set_header('Sec-WebSocket-Protocol', protocol_header)

        if extra_headers is not None:
            if callable(extra_headers):
                extra_headers = extra_headers(path, self.raw_request_headers)
            if isinstance(extra_headers, collections.abc.Mapping):
                extra_headers = extra_headers.items()
            for name, value in extra_headers:
                set_header(name, value)

        if not is_header_set('Server'):
            set_header('Server', USER_AGENT)

        build_response(set_header, key)

        yield from self.write_http_response(
            SWITCHING_PROTOCOLS, response_headers)

        self.connection_open()

        return path


class WebSocketServer:
    """
    Wrapper for :class:`~asyncio.Server` that closes connections on exit.

    This class provides the return type of :func:`~websockets.server.serve`.

    It mimics the interface of :class:`~asyncio.AbstractServer`, namely its
    :meth:`~asyncio.AbstractServer.close()` and
    :meth:`~asyncio.AbstractServer.wait_closed()` methods, to close WebSocket
    connections properly on exit, in addition to closing the underlying
    :class:`~asyncio.Server`.

    Instances of this class store a reference to the :class:`~asyncio.Server`
    object returned by :meth:`~asyncio.AbstractEventLoop.create_server` rather
    than inherit from :class:`~asyncio.Server` in part because
    :meth:`~asyncio.AbstractEventLoop.create_server` doesn't support passing a
    custom :class:`~asyncio.Server` class.

    """
    def __init__(self, loop):
        # Store a reference to loop to avoid relying on self.server._loop.
        self.loop = loop

        self.closing = False
        self.websockets = set()

    def wrap(self, server):
        """
        Attach to a given :class:`~asyncio.Server`.

        Since :meth:`~asyncio.AbstractEventLoop.create_server` doesn't support
        injecting a custom ``Server`` class, the easiest solution that doesn't
        rely on private :mod:`asyncio` APIs is to:

        - instantiate a :class:`WebSocketServer`
        - give the protocol factory a reference to that instance
        - call :meth:`~asyncio.AbstractEventLoop.create_server` with the
          factory
        - attach the resulting :class:`~asyncio.Server` with this method

        """
        self.server = server

    def register(self, protocol):
        """
        Register a connection with this server.

        """
        self.websockets.add(protocol)

    def unregister(self, protocol):
        """
        Unregister a connection with this server.

        """
        self.websockets.remove(protocol)

    def close(self):
        """
        Close the underlying server, and clean up connections.

        This calls :meth:`~asyncio.Server.close` on the underlying
        :class:`~asyncio.Server` object, closes open connections with
        status code 1001, and stops accepting new connections.

        """
        # Make a note that the server is shutting down. Websocket connections
        # check this attribute to decide to send a "going away" close code.
        self.closing = True

        # Stop accepting new connections.
        self.server.close()

        # Close open connections. For each connection, two tasks are running:
        # 1. self.transfer_data_task receives incoming WebSocket messages
        # 2. self.handler_task runs the opening handshake, the handler provided
        #    by the user and the closing handshake
        # In the general case, cancelling the handler task will cause the
        # handler provided by the user to exit with a CancelledError, which
        # will then cause the transfer data task to terminate.
        for websocket in self.websockets:
            websocket.handler_task.cancel()

    @asyncio.coroutine
    def wait_closed(self):
        """
        Wait until the underlying server and all connections are closed.

        This calls :meth:`~asyncio.Server.wait_closed` on the underlying
        :class:`~asyncio.Server` object and waits until closing handshakes
        are complete and all connections are closed.

        This method must be called after :meth:`close()`.

        """
        # asyncio.wait doesn't accept an empty first argument.
        if self.websockets:
            # Either the handler or the connection can terminate first,
            # depending on how the client behaves and the server is
            # implemented.
            yield from asyncio.wait(
                [websocket.handler_task for websocket in self.websockets] +
                [websocket.close_connection_task
                    for websocket in self.websockets],
                loop=self.loop)
        yield from self.server.wait_closed()

    @property
    def sockets(self):
        """
        List of :class:`~socket.socket` objects the server is listening to.

        ``None`` if the server is closed.

        """
        return self.server.sockets


class Serve:
    """
    This coroutine creates, starts, and return a :class:`WebSocketServer`.

    :func:`serve` is a wrapper around the event loop's
    :meth:`~asyncio.AbstractEventLoop.create_server` method. Internally, the
    function creates and starts a :class:`~asyncio.Server` object by calling
    :meth:`~asyncio.AbstractEventLoop.create_server`. The
    :class:`WebSocketServer` keeps a reference to this object.

    The returned :class:`WebSocketServer` and its resources can be cleaned up
    by calling its :meth:`~websockets.server.WebSocketServer.close` and
    :meth:`~websockets.server.WebSocketServer.wait_closed` methods.

    On Python ≥ 3.5, :func:`serve` can also be used as an asynchronous context
    manager. In this case, the server is shut down when exiting the context.

    The ``ws_handler`` argument is the WebSocket handler. It must be a
    coroutine accepting two arguments: a :class:`WebSocketServerProtocol` and
    the request URI.

    The ``host`` and ``port`` arguments, as well as unrecognized keyword
    arguments, are passed along to
    :meth:`~asyncio.AbstractEventLoop.create_server`. For example, you can set
    the ``ssl`` keyword argument to a :class:`~ssl.SSLContext` to enable TLS.

    The ``create_protocol`` parameter allows customizing the asyncio protocol
    that manages the connection. It should be a callable or class accepting
    the same arguments as :class:`WebSocketServerProtocol` and returning a
    :class:`WebSocketServerProtocol` instance. It defaults to
    :class:`WebSocketServerProtocol`.

    The behavior of the ``timeout``, ``max_size``, and ``max_queue``,
    ``read_limit``, and ``write_limit`` optional arguments is described in the
    documentation of :class:`~websockets.protocol.WebSocketCommonProtocol`.

    :func:`serve` also accepts the following optional arguments:

    * ``origins`` defines acceptable Origin HTTP headers — include ``''`` if
      the lack of an origin is acceptable
    * ``extensions`` is a list of supported extensions in order of
      decreasing preference
    * ``subprotocols`` is a list of supported subprotocols in order of
      decreasing preference
    * ``extra_headers`` sets additional HTTP response headers — it can be a
      mapping, an iterable of (name, value) pairs, or a callable taking the
      request path and headers in arguments.
    * ``compression`` is a shortcut to configure compression extensions;
      by default it enables the "permessage-deflate" extension; set it to
      ``None`` to disable compression

    Whenever a client connects, the server accepts the connection, creates a
    :class:`WebSocketServerProtocol`, performs the opening handshake, and
    delegates to the WebSocket handler. Once the handler completes, the server
    performs the closing handshake and closes the connection.

    Since there's no useful way to propagate exceptions triggered in handlers,
    they're sent to the ``'websockets.server'`` logger instead. Debugging is
    much easier if you configure logging to print them::

        import logging
        logger = logging.getLogger('websockets.server')
        logger.setLevel(logging.ERROR)
        logger.addHandler(logging.StreamHandler())

    """

    def __init__(self, ws_handler, host=None, port=None, *,
                 path=None, create_protocol=None,
                 timeout=10, max_size=2 ** 20, max_queue=2 ** 5,
                 read_limit=2 ** 16, write_limit=2 ** 16,
                 loop=None, legacy_recv=False, klass=None,
                 origins=None, extensions=None, subprotocols=None,
                 extra_headers=None, compression='deflate', **kwds):
        # Backwards-compatibility: create_protocol used to be called klass.
        # In the unlikely event that both are specified, klass is ignored.
        if create_protocol is None:
            create_protocol = klass

        if create_protocol is None:
            create_protocol = WebSocketServerProtocol

        if loop is None:
            loop = asyncio.get_event_loop()

        ws_server = WebSocketServer(loop)

        secure = kwds.get('ssl') is not None

        if compression == 'deflate':
            if extensions is None:
                extensions = []
            if not any(
                extension_factory.name == ServerPerMessageDeflateFactory.name
                for extension_factory in extensions
            ):
                extensions.append(ServerPerMessageDeflateFactory())
        elif compression is not None:
            raise ValueError("Unsupported compression: {}".format(compression))

        factory = lambda: create_protocol(
            ws_handler, ws_server,
            host=host, port=port, secure=secure,
            timeout=timeout, max_size=max_size, max_queue=max_queue,
            read_limit=read_limit, write_limit=write_limit,
            loop=loop, legacy_recv=legacy_recv,
            origins=origins, extensions=extensions, subprotocols=subprotocols,
            extra_headers=extra_headers,
        )

        if path is None:
            creating_server = loop.create_server(factory, host, port, **kwds)
        else:
            creating_server = loop.create_unix_server(factory, path, **kwds)

        # This is a coroutine object.
        self._creating_server = creating_server
        self.ws_server = ws_server

    @asyncio.coroutine
    def __aenter__(self):
        return (yield from self)

    @asyncio.coroutine
    def __aexit__(self, exc_type, exc_value, traceback):
        self.ws_server.close()
        yield from self.ws_server.wait_closed()

    def __await__(self):
        server = yield from self._creating_server
        self.ws_server.wrap(server)
        return self.ws_server

    __iter__ = __await__


@asyncio.coroutine
def unix_serve(ws_handler, path, **kwargs):
    """
    Similar to :func:`serve()`, but for listening on Unix sockets.

    This function calls the event loop's
    :meth:`~asyncio.AbstractEventLoop.create_unix_server` method.

    It is only available on Unix.

    It's useful for deploying a server behind a reverse proxy such as nginx.

    """
    return serve(ws_handler, path=path, **kwargs)


if sys.version_info[:2] <= (3, 4):                          # pragma: no cover
    @asyncio.coroutine
    def serve(*args, **kwds):
        return Serve(*args, **kwds).__await__()
    serve.__doc__ = Serve.__doc__

else:
    serve = Serve
