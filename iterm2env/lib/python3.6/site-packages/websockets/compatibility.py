"""
The :mod:`websockets.compatibility` module provides helpers for bridging
compatibility issues across Python versions.

"""

import asyncio
import http


# Replace with BaseEventLoop.create_task when dropping Python < 3.4.2.
try:                                                # pragma: no cover
    asyncio_ensure_future = asyncio.ensure_future   # Python ≥ 3.5
except AttributeError:                              # pragma: no cover
    asyncio_ensure_future = asyncio.async           # Python < 3.5

try:                                                # pragma: no cover
                                                    # Python ≥ 3.5
    SWITCHING_PROTOCOLS = http.HTTPStatus.SWITCHING_PROTOCOLS
    OK = http.HTTPStatus.OK
    BAD_REQUEST = http.HTTPStatus.BAD_REQUEST
    UNAUTHORIZED = http.HTTPStatus.UNAUTHORIZED
    FORBIDDEN = http.HTTPStatus.FORBIDDEN
    INTERNAL_SERVER_ERROR = http.HTTPStatus.INTERNAL_SERVER_ERROR
    SERVICE_UNAVAILABLE = http.HTTPStatus.SERVICE_UNAVAILABLE
except AttributeError:                              # pragma: no cover
                                                    # Python < 3.5
    class SWITCHING_PROTOCOLS:
        value = 101
        phrase = "Switching Protocols"

    class OK:
        value = 200
        phrase = "OK"

    class BAD_REQUEST:
        value = 400
        phrase = "Bad Request"

    class UNAUTHORIZED:
        value = 401
        phrase = "Unauthorized"

    class FORBIDDEN:
        value = 403
        phrase = "Forbidden"

    class INTERNAL_SERVER_ERROR:
        value = 500
        phrase = "Internal Server Error"

    class SERVICE_UNAVAILABLE:
        value = 503
        phrase = "Service Unavailable"
