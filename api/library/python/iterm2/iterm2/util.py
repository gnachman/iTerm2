"""Provides handy functions."""
import json

class Size:
  """Describes a 2D size.

  Can be used where api_pb2.Size is accepted."""

  def __init__(self, width, height):
    """Constructs a new size.

    :param width: A nonnegative number giving the width.
    :param height: A nonnegative number giving the height.
    """
    self.__width = width
    self.__height = height

  @property
  def width(self):
    return self.__width

  @width.setter
  def width(self, value):
    self.__width = value

  @property
  def height(self):
    return self.__height

  @height.setter
  def height(self, value):
    self.__height = value

  @property
  def dict(self):
    """
    Returns a dict representation of the size.
    """
    return {"width": self.width, "height": self.height}

  def load_from_dict(self, dict):
    """
    Initializes the size from a dict representation.
    """
    self.width = dict["width"]
    self.height = dict["height"]

  @property
  def json(self):
    """
    Gives a JSON representation of the size.
    """
    return json.dumps(self.dict)

class Point:
  """Describes a 2D coordinate.

  Can be used where api_pb2.Point is accepted."""

  def __init__(self, x, y):
    """Constructs a new point.

    :param x: A number giving the X coordinate.
    :param y: A number giving the Y coordinate.
    """
    self.__x = x
    self.__y = y

  @property
  def x(self):
    return self.__x

  @x.setter
  def x(self, value):
    self.__x = value

  @property
  def y(self):
    return self.__y

  @y.setter
  def y(self, value):
    self.__y = value

  @property
  def dict(self):
    """Returns a dict representation of the point."""
    return {"x": self.x, "y": self.y}

  def load_from_dict(self, dict):
      """Initializes the point from a dict representation."""
      self.x = dict["x"]
      self.y = dict["y"]

  @property
  def json(self):
    """Returns a JSON representation of the point."""
    return json.dumps(self.dict)

class Frame:
  """Describes a bounding rectangle. 0,0 is the bottom left coordinate."""
  def __init__(self, origin=Point(0, 0), size=Size(0, 0)):
    """Constructs a new frame."""
    self.__origin = origin
    self.__size = size

  @property
  def origin(self):
    return self.__origin

  @origin.setter
  def origin(self, value):
    self.__origin = value

  @property
  def size(self):
    return self.__size

  @size.setter
  def size(self, value):
    self.__size = value

  def load_from_dict(self, dict):
    """Sets the frame's values from a dict representation."""
    self.origin.load_from_dict(dict["origin"])
    self.size.load_from_dict(dict["size"])

  @property
  def dict(self):
    """Returns a dict representation of the frame."""
    return {"origin": self.origin.dict, "size": self.size.dict}

  @property
  def json(self):
    """Returns a JSON representation of the frame."""
    return json.dumps(self.dict)

def frame_str(frame):
    """Formats an api_pb2.Frame or :class:`Frame` as a human-readable string.

    :param frame: An api_pb2.Frame or :class:`Frame`

    :returns: A human-readable string."""
    if frame is None:
        return "[Undefined]"

    return "[(%s, %s) %s]" % (
        frame.origin.x,
        frame.origin.y,
        size_str(frame.size))

def size_str(size):
    """Formats an api_pb2.Size or :class:`Size` as a human-readable string.

    :param frame: An api_pb2.Size or :class:`Size`:

    :returns: A human-readable string."""
    if size is None:
        return "[Undefined]"
    return "(%s x %s)" % (
        size.width,
        size.height)

def point_str(point):
    """Formats an api_pb2.Point or :class:`Point` as a human-readable string.

        :param frame: An api_pb2.Point or :class:`Point`

        :returns: A human-readable string."""
    if point is None:
        return "[Undefined]"
    return "(%s, %s)" % (point.x,
                          point.y)
