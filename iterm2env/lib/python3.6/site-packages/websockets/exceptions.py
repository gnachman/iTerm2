__all__ = [
    'AbortHandshake', 'InvalidHandshake', 'InvalidHeader', 'InvalidMessage',
    'InvalidOrigin', 'InvalidState', 'InvalidStatusCode', 'NegotiationError',
    'InvalidParameterName', 'InvalidParameterValue', 'DuplicateParameter',
    'InvalidURI', 'ConnectionClosed', 'PayloadTooBig',
    'WebSocketProtocolError',
]


class InvalidHandshake(Exception):
    """
    Exception raised when a handshake request or response is invalid.

    """


class AbortHandshake(InvalidHandshake):
    """
    Exception raised to abort a handshake and return a HTTP response.

    """
    def __init__(self, status, headers, body=None):
        self.status = status
        self.headers = headers
        self.body = body
        message = "HTTP {}, {} headers, {} bytes".format(
            status, len(headers), 0 if body is None else len(body))
        super().__init__(message)


class InvalidMessage(InvalidHandshake):
    """
    Exception raised when the HTTP message in a handshake request is malformed.

    """


class InvalidHeader(InvalidHandshake):
    """
    Exception raised when a HTTP header doesn't have the expected format.

    """
    def __init__(self, message, string, pos):
        self.string = string
        self.pos = pos
        message = "{} at {} in {}".format(message, pos, string)
        super().__init__(message)


class InvalidOrigin(InvalidHandshake):
    """
    Exception raised when the origin in a handshake request is forbidden.

    """


class InvalidStatusCode(InvalidHandshake):
    """
    Exception raised when a handshake response status code is invalid.

    Provides the integer status code in its ``status_code`` attribute.

    """
    def __init__(self, status_code):
        self.status_code = status_code
        message = "Status code not 101: {}".format(status_code)
        super().__init__(message)


class NegotiationError(InvalidHandshake):
    """
    Exception raised when negociating an extension fails.

    """


class InvalidParameterName(NegotiationError):
    """
    Exception raised when a parameter name in an extension header is invalid.

    """
    def __init__(self, name):
        self.name = name
        message = "Invalid parameter name: {}".format(name)
        super().__init__(message)


class InvalidParameterValue(NegotiationError):
    """
    Exception raised when a parameter value in an extension header is invalid.

    """
    def __init__(self, name, value):
        self.name = name
        self.value = value
        message = "Invalid value for parameter {}: {}".format(name, value)
        super().__init__(message)


class DuplicateParameter(NegotiationError):
    """
    Exception raised when a parameter name is repeated in an extension header.

    """
    def __init__(self, name):
        self.name = name
        message = "Duplicate parameter: {}".format(name)
        super().__init__(message)


class InvalidState(Exception):
    """
    Exception raised when an operation is forbidden in the current state.

    """


CLOSE_CODES = {
    1000: "OK",
    1001: "going away",
    1002: "protocol error",
    1003: "unsupported type",
    # 1004 is reserved
    1005: "no status code [internal]",
    1006: "connection closed abnormally [internal]",
    1007: "invalid data",
    1008: "policy violation",
    1009: "message too big",
    1010: "extension required",
    1011: "unexpected error",
    1015: "TLS failure [internal]",
}


class ConnectionClosed(InvalidState):
    """
    Exception raised when trying to read or write on a closed connection.

    Provides the connection close code and reason in its ``code`` and
    ``reason`` attributes respectively.

    """
    def __init__(self, code, reason):
        self.code = code
        self.reason = reason
        message = "WebSocket connection is closed: "
        if 3000 <= code < 4000:
            explanation = "registered"
        elif 4000 <= code < 5000:
            explanation = "private use"
        else:
            explanation = CLOSE_CODES.get(code, "unknown")
        message += "code = {} ({}), ".format(code, explanation)
        if reason:
            message += "reason = {}".format(reason)
        else:
            message += "no reason"
        super().__init__(message)


class InvalidURI(Exception):
    """
    Exception raised when an URI isn't a valid websocket URI.

    """


class PayloadTooBig(Exception):
    """
    Exception raised when a frame's payload exceeds the maximum size.

    """


class WebSocketProtocolError(Exception):
    """
    Internal exception raised when the remote side breaks the protocol.

    """
