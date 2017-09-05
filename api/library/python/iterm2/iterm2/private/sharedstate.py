import socket

_socket = None
_notification_handlers = []

def register_notification_handler(handler):
  _notification_handlers.append(handler)

def _notification_handler(notification):
  for handler in _notification_handlers:
    handler(notification)

def get_socket():
  global _socket
  if _socket is None:
    _socket = socket.Connection()
    _socket.connect(_notification_handler)
  return _socket

def wait():
  if _socket is not None:
    _socket.wait()


