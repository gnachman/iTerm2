"""Provides handy functions."""
import json

class Size:
  """Describes a 2D size.

  Can be where api_pb2.Size is accepted."""
  def __init__(self, width, height):
    self.width = width
    self.height = height

  @property
  def json(self):
    return json.dumps({"width": self.width, "height": self.height})

def frame_str(frame):
    """Formats an api_pb2.Frame as a human-readable string.

    :param frame: An api_pb2.Frame

    :returns: A human-readable string."""
    if frame is None:
        return "[Undefined]"

    return "[(%s, %s) %s]" % (
        frame.origin.x,
        frame.origin.y,
        size_str(frame.size))

def size_str(size):
    """Formats an api_pb2.Size as a human-readable string.

    :param frame: An api_pb2.Size

    :returns: A human-readable string."""
    if size is None:
        return "[Undefined]"
    return "(%s x %s)" % (
        size.width,
        size.height)
