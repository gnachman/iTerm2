"""Provides handy functions."""
import asyncio
import json
import iterm2.api_pb2
import typing

class Size:
  """Describes a 2D size.

  Can be used where api_pb2.Size is accepted."""

  def __init__(self, width: float, height: float):
    """Constructs a new size.

    :param width: A nonnegative number giving the width.
    :param height: A nonnegative number giving the height.
    """
    self.__width = width
    self.__height = height

  @property
  def width(self) -> float:
    return self.__width

  @width.setter
  def width(self, value: float):
    self.__width = value

  @property
  def height(self) -> float:
    return self.__height

  @height.setter
  def height(self, value: float):
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
  def json(self) -> str:
    """
    Gives a JSON representation of the size.
    """
    return json.dumps(self.dict)

  @property
  def proto(self):
      p = iterm2.api_pb2.Size()
      p.width = self.width
      p.height = self.height
      return p

class Point:
  """Describes a 2D coordinate.

  Can be used where api_pb2.Point is accepted."""

  def __init__(self, x: float, y: float):
    """Constructs a new point.

    :param x: A number giving the X coordinate.
    :param y: A number giving the Y coordinate.
    """
    self.__x = x
    self.__y = y

  def __repr__(self):
    return "({}, {})".format(self.x, self.y)

  @staticmethod
  def from_coord_proto(proto):
      return Point(proto.x, proto.y)

  @property
  def x(self) -> float:
    return self.__x

  @x.setter
  def x(self, value: float):
    self.__x = value

  @property
  def y(self) -> float:
    return self.__y

  @y.setter
  def y(self, value: float):
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
  def json(self) -> str:
    """Returns a JSON representation of the point."""
    return json.dumps(self.dict)

  @property
  def proto(self):
      p = iterm2.api_pb2.Coord()
      p.x = self.x
      p.y = self.y
      return p

  def __eq__(self, other):
    if isinstance(other, Point):
        return self.x == other.x and self.y == other.y
    return NotImplemented

  def __hash__(self):
    return hash(tuple(sorted(self.__dict__.items())))

class Frame:
  """Describes a bounding rectangle. 0,0 is the bottom left coordinate."""
  def __init__(self, origin: Point=Point(0, 0), size: Size=Size(0, 0)):
    """Constructs a new frame."""
    self.__origin = origin
    self.__size = size

  def __repr__(self):
    return "<Frame origin={} size={}>".format(self.origin, self.size)

  @property
  def origin(self) -> Point:
    """The top-left coordinate.

    :returns: A :class:`Point`.
    """
    return self.__origin

  @origin.setter
  def origin(self, value: Point):
    """Sets the top-left coordinate.

    :param value: A :class:`Point`.
    """
    self.__origin = value

  @property
  def size(self) -> Size:
    """The size.

    :returns: A :class:`Size`.
    """
    return self.__size

  @size.setter
  def size(self, value: Size):
    """Sets the size.

    :param value: A :class:`Size`.
    """
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
  def json(self) -> str:
    """Returns a JSON representation of the frame."""
    return json.dumps(self.dict)

def frame_str(frame: Frame) -> str:
    """Formats a :class:`Frame` as a human-readable string.

    :param frame: The frame to convert.

    :returns: A human-readable string."""
    if frame is None:
        return "[Undefined]"

    return "[(%s, %s) %s]" % (
        frame.origin.x,
        frame.origin.y,
        size_str(frame.size))

def size_str(size: Size) -> str:
    """Formats a :class:`Size` as a human-readable string.

    :param size: The size to convert.

    :returns: A human-readable string."""
    if size is None:
        return "[Undefined]"
    return "(%s x %s)" % (
        size.width,
        size.height)

def point_str(point: Point) -> str:
    """Formats a :class:`Point` as a human-readable string.

    :param point: The point to convert.

    :returns: A human-readable string."""
    if point is None:
        return "[Undefined]"
    return "(%s, %s)" % (point.x,
                          point.y)

def distance(a, b, gridWidth):
    aPos = a.y;
    aPos *= gridWidth;
    aPos += a.x;

    bPos = b.y;
    bPos *= gridWidth;
    bPos += b.x;

    return abs(aPos - bPos);


class CoordRange:
    """Describes a range of contiguous cells.

    :param start: The start point.
    :param end: The first point after the start point not in the range."""
    def __init__(self, start: Point, end: Point):
        self.__start = start
        self.__end = end

    def __repr__(self):
        return "CoordRange({} to {})".format(self.start, self.end)

    @staticmethod
    def from_proto(proto):
        return CoordRange(
                Point.from_coord_proto(proto.start),
                Point.from_coord_proto(proto.end))

    @property
    def start(self) -> Point:
        """:returns: The start :class:`Point`."""
        return self.__start

    @property
    def end(self) -> Point:
        """:returns: The first :class:`Point` after `self.start` not in the range."""
        return self.__end

    @property
    def proto(self):
        p = iterm2.api_pb2.CoordRange()
        p.start.CopyFrom(self.start.proto)
        p.end.CopyFrom(self.end.proto)
        return p

    def length(self, width) -> int:
        return distance(self.start, self.end, width)

class Range:
    """Describes a range of integers.

    :param location: The first value in the range.
    :param length: The number of values in the range."""
    def __init__(self, location: int, length: int):
        self.__location = location
        self.__length = length

    def __repr__(self):
        return "[{}, {})".format(self.location, self.location + self.length)

    @property
    def location(self) -> int:
        """:returns: The first location of the range."""
        return self.__location

    @property
    def length(self) -> int:
        """:returns: The length of the range."""
        return self.__length

    @property
    def max(self) -> int:
      return self.location + self.length

    @property
    def proto(self):
        p = iterm2.api_pb2.Range()
        p.location = self.location
        p.length = self.length
        return p

    @property
    def toSet(self):
        return set(range(self.location, self.location + self.length))

class WindowedCoordRange:
    """Describes a range of coordinates, optionally constrained to a continugous range of columns.

    :param coordRange: The range of cells.
    :param columnRange: The range of columns to intersect with `coordRange` to get the described region, or `None` if unwindowed.
    """
    def __init__(self, coordRange: CoordRange, columnRange: typing.Optional[Range]=None):
        self.__coordRange = coordRange
        if columnRange:
            self.__columnRange = columnRange
        else:
            self.__columnRange = Range(0, 0)

    def __repr__(self):
        return "WindowedCoordRange(coordRange={} cols={})".format(self.coordRange, self.columnRange)

    @property
    def coordRange(self) -> CoordRange:
        """:returns: The range of coordinates."""
        return self.__coordRange

    @property
    def columnRange(self) -> Range:
        """:returns: The range of columns, or an empty range if unconstrained."""
        return self.__columnRange

    @property
    def proto(self):
        p = iterm2.api_pb2.WindowedCoordRange()
        p.coord_range.CopyFrom(self.coordRange.proto)
        p.columns.CopyFrom(self.columnRange.proto)
        return p

    @property
    def start(self) -> Point:
        """The first point in the region."""
        x, y = self.coordRange.start.x, self.coordRange.start.y;
        if self.columnRange.length:
            x = min(max(x, self.columnRange.location),
                          self.columnRange.location + self.columnRange.length)
        return Point(x, y)

    @property
    def end(self) -> Point:
        """The first point not in the region."""
        x, y = self.coordRange.end.x, self.coordRange.end.y
        if self.hasWindow:
            x = min(self.coordRange.end.x, self.right + 1)
        return Point(x, y)

    @property
    def right(self) -> int:
        """The rightmost column allowed, or 0 if unwindowed."""
        return self.__columnRange.location + self.__columnRange.length

    @property
    def left(self) -> int:
        """The leftmost column allowed."""
        if self.hasWindow:
            return self.__columnRange.location
        else:
            return 0

    @property
    def hasWindow(self) -> bool:
        """Are the columns constrained?"""
        return self.__columnRange.length > 0

async def async_wait_forever():
    """A convenience function that never returns."""
    await asyncio.wait([asyncio.Future()])

