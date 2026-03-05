"""Tests for iterm2.util module."""
import json
import pytest
from iterm2.util import (
    Size, Point, Frame, Range, CoordRange, WindowedCoordRange,
    frame_str, size_str, point_str, distance,
    iterm2_encode, iterm2_encode_str, iterm2_encode_list, invocation_string
)


class TestSize:
    """Tests for the Size class."""

    def test_init(self):
        """Test Size initialization."""
        size = Size(100, 200)
        assert size.width == 100
        assert size.height == 200

    def test_setters(self):
        """Test Size property setters."""
        size = Size(0, 0)
        size.width = 50
        size.height = 75
        assert size.width == 50
        assert size.height == 75

    def test_dict(self):
        """Test Size dict property."""
        size = Size(10, 20)
        assert size.dict == {"width": 10, "height": 20}

    def test_load_from_dict(self):
        """Test Size load_from_dict."""
        size = Size(0, 0)
        size.load_from_dict({"width": 30, "height": 40})
        assert size.width == 30
        assert size.height == 40

    def test_json(self):
        """Test Size JSON property."""
        size = Size(5, 10)
        parsed = json.loads(size.json)
        assert parsed == {"width": 5, "height": 10}


class TestPoint:
    """Tests for the Point class."""

    def test_init(self):
        """Test Point initialization."""
        point = Point(10, 20)
        assert point.x == 10
        assert point.y == 20

    def test_setters(self):
        """Test Point property setters."""
        point = Point(0, 0)
        point.x = 5
        point.y = 15
        assert point.x == 5
        assert point.y == 15

    def test_repr(self):
        """Test Point string representation."""
        point = Point(3, 7)
        assert repr(point) == "(3, 7)"

    def test_dict(self):
        """Test Point dict property."""
        point = Point(1, 2)
        assert point.dict == {"x": 1, "y": 2}

    def test_load_from_dict(self):
        """Test Point load_from_dict."""
        point = Point(0, 0)
        point.load_from_dict({"x": 100, "y": 200})
        assert point.x == 100
        assert point.y == 200

    def test_json(self):
        """Test Point JSON property."""
        point = Point(8, 9)
        parsed = json.loads(point.json)
        assert parsed == {"x": 8, "y": 9}

    def test_equality(self):
        """Test Point equality."""
        p1 = Point(5, 10)
        p2 = Point(5, 10)
        p3 = Point(5, 11)
        assert p1 == p2
        assert p1 != p3

    def test_hash(self):
        """Test Point is hashable."""
        p1 = Point(5, 10)
        p2 = Point(5, 10)
        # Points with same values should work as dict keys
        d = {p1: "value"}
        assert p2 in d or hash(p1) == hash(p2)


class TestFrame:
    """Tests for the Frame class."""

    def test_init_defaults(self):
        """Test Frame default initialization."""
        frame = Frame()
        assert frame.origin.x == 0
        assert frame.origin.y == 0
        assert frame.size.width == 0
        assert frame.size.height == 0

    def test_init_with_values(self):
        """Test Frame initialization with values."""
        origin = Point(10, 20)
        size = Size(100, 200)
        frame = Frame(origin, size)
        assert frame.origin.x == 10
        assert frame.origin.y == 20
        assert frame.size.width == 100
        assert frame.size.height == 200

    def test_setters(self):
        """Test Frame property setters."""
        frame = Frame()
        frame.origin = Point(5, 10)
        frame.size = Size(50, 100)
        assert frame.origin.x == 5
        assert frame.size.width == 50

    def test_repr(self):
        """Test Frame string representation."""
        frame = Frame(Point(1, 2), Size(3, 4))
        assert "origin" in repr(frame).lower() or "1" in repr(frame)

    def test_load_from_dict(self):
        """Test Frame load_from_dict."""
        frame = Frame()
        frame.load_from_dict({
            "origin": {"x": 10, "y": 20},
            "size": {"width": 30, "height": 40}
        })
        assert frame.origin.x == 10
        assert frame.origin.y == 20
        assert frame.size.width == 30
        assert frame.size.height == 40

    def test_dict(self):
        """Test Frame dict property."""
        frame = Frame(Point(1, 2), Size(3, 4))
        d = frame.dict
        assert d["origin"] == {"x": 1, "y": 2}
        assert d["size"] == {"width": 3, "height": 4}

    def test_json(self):
        """Test Frame JSON property."""
        frame = Frame(Point(1, 2), Size(3, 4))
        parsed = json.loads(frame.json)
        assert parsed["origin"]["x"] == 1
        assert parsed["size"]["height"] == 4


class TestRange:
    """Tests for the Range class."""

    def test_init(self):
        """Test Range initialization."""
        r = Range(10, 5)
        assert r.location == 10
        assert r.length == 5

    def test_max(self):
        """Test Range max property."""
        r = Range(10, 5)
        assert r.max == 15

    def test_to_set(self):
        """Test Range to_set property."""
        r = Range(3, 4)
        assert r.to_set == {3, 4, 5, 6}

    def test_repr(self):
        """Test Range string representation."""
        r = Range(5, 3)
        # Should represent as [location, location + length)
        assert "[5, 8)" == repr(r)


class TestCoordRange:
    """Tests for the CoordRange class."""

    def test_init(self):
        """Test CoordRange initialization."""
        start = Point(0, 0)
        end = Point(10, 5)
        cr = CoordRange(start, end)
        assert cr.start.x == 0
        assert cr.start.y == 0
        assert cr.end.x == 10
        assert cr.end.y == 5

    def test_length(self):
        """Test CoordRange length calculation."""
        # In a grid of width 80, from (0,0) to (0,1) is 80 cells
        start = Point(0, 0)
        end = Point(0, 1)
        cr = CoordRange(start, end)
        assert cr.length(80) == 80

    def test_repr(self):
        """Test CoordRange string representation."""
        cr = CoordRange(Point(1, 2), Point(3, 4))
        assert "1" in repr(cr) and "2" in repr(cr)


class TestWindowedCoordRange:
    """Tests for the WindowedCoordRange class."""

    def test_init_no_window(self):
        """Test WindowedCoordRange without column constraint."""
        cr = CoordRange(Point(0, 0), Point(10, 5))
        wcr = WindowedCoordRange(cr)
        assert wcr.coordRange.start.x == 0
        assert wcr.has_window is False

    def test_init_with_window(self):
        """Test WindowedCoordRange with column constraint."""
        cr = CoordRange(Point(0, 0), Point(10, 5))
        col_range = Range(5, 10)
        wcr = WindowedCoordRange(cr, col_range)
        assert wcr.has_window is True
        assert wcr.columnRange.location == 5
        assert wcr.columnRange.length == 10

    def test_left_right(self):
        """Test left and right properties."""
        cr = CoordRange(Point(0, 0), Point(20, 5))
        col_range = Range(5, 10)
        wcr = WindowedCoordRange(cr, col_range)
        assert wcr.left == 5
        assert wcr.right == 15

    def test_start_constrained(self):
        """Test start point is constrained by window."""
        cr = CoordRange(Point(0, 0), Point(20, 5))
        col_range = Range(5, 10)
        wcr = WindowedCoordRange(cr, col_range)
        # Start x=0 should be clamped to column 5
        assert wcr.start.x == 5
        assert wcr.start.y == 0


class TestHelperFunctions:
    """Tests for utility helper functions."""

    def test_size_str(self):
        """Test size_str function."""
        size = Size(100, 200)
        result = size_str(size)
        assert "100" in result
        assert "200" in result

    def test_size_str_none(self):
        """Test size_str with None."""
        assert "[Undefined]" == size_str(None)

    def test_point_str(self):
        """Test point_str function."""
        point = Point(10, 20)
        result = point_str(point)
        assert "10" in result
        assert "20" in result

    def test_point_str_none(self):
        """Test point_str with None."""
        assert "[Undefined]" == point_str(None)

    def test_frame_str(self):
        """Test frame_str function."""
        frame = Frame(Point(5, 10), Size(100, 200))
        result = frame_str(frame)
        assert "5" in result
        assert "10" in result
        assert "100" in result
        assert "200" in result

    def test_frame_str_none(self):
        """Test frame_str with None."""
        assert "[Undefined]" == frame_str(None)

    def test_distance(self):
        """Test distance function."""
        # Distance in a grid of width 10
        # From (0,0) to (5,0) = 5 cells
        assert distance(Point(0, 0), Point(5, 0), 10) == 5
        # From (0,0) to (0,1) = 10 cells (one row)
        assert distance(Point(0, 0), Point(0, 1), 10) == 10
        # From (0,0) to (5,1) = 15 cells
        assert distance(Point(0, 0), Point(5, 1), 10) == 15


class TestIterm2Encode:
    """Tests for iTerm2 encoding functions."""

    def test_encode_str(self):
        """Test iterm2_encode_str function."""
        assert iterm2_encode_str("hello") == '"hello"'

    def test_encode_str_with_quotes(self):
        """Test encoding string with embedded quotes."""
        assert iterm2_encode_str('say "hi"') == '"say \\"hi\\""'

    def test_encode_str_with_backslash(self):
        """Test encoding string with backslash."""
        assert iterm2_encode_str("path\\to") == '"path\\\\to"'

    def test_encode_list(self):
        """Test iterm2_encode_list function."""
        assert iterm2_encode_list(["a", "b"]) == '["a", "b"]'

    def test_encode_number(self):
        """Test iterm2_encode with number."""
        assert iterm2_encode(42) == "42"
        assert iterm2_encode(3.14) == "3.14"

    def test_encode_mixed(self):
        """Test iterm2_encode with mixed types."""
        result = iterm2_encode(["hello", 42])
        assert result == '["hello", 42]'


class TestInvocationString:
    """Tests for invocation_string function."""

    def test_simple_invocation(self):
        """Test simple method invocation string."""
        result = invocation_string("myMethod", {"arg1": "value1"})
        assert result == 'myMethod(arg1: "value1")'

    def test_multiple_args(self):
        """Test invocation with multiple arguments."""
        result = invocation_string("func", {"a": 1, "b": "two"})
        assert "func(" in result
        assert "a: 1" in result
        assert 'b: "two"' in result

    def test_empty_args(self):
        """Test invocation with no arguments."""
        result = invocation_string("noArgs", {})
        assert result == "noArgs()"
