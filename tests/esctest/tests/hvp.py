import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class HVPTests(object):
  def test_HVP_DefaultParams(self):
    """With no params, HVP moves to 1,1."""
    esccmd.HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccmd.HVP()

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

  def test_HVP_RowOnly(self):
    """Default column is 1."""
    esccmd.HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccmd.HVP(row=2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 2)

  def test_HVP_ColumnOnly(self):
    """Default row is 1."""
    esccmd.HVP(Point(6, 3))

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

    esccmd.HVP(col=2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 2)
    AssertEQ(position.y(), 1)

  def test_HVP_ZeroIsTreatedAsOne(self):
    """Zero args are treated as 1."""
    esccmd.HVP(Point(6, 3))
    esccmd.HVP(col=0, row=0)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

  def test_HVP_OutOfBoundsParams(self):
    """With overly large parameters, HVP moves as far as possible down and right."""
    size = GetScreenSize()
    esccmd.HVP(Point(size.width() + 10, size.height() + 10))

    position = GetCursorPosition()
    AssertEQ(position.x(), size.width())
    AssertEQ(position.y(), size.height())

  def test_HVP_RespectsOriginMode(self):
    """HVP is relative to margins in origin mode."""
    # Set a scroll region.
    esccmd.DECSTBM(6, 11)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Move to center of region
    esccmd.HVP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 9)

    # Turn on origin mode.
    esccmd.DECSET(esccmd.DECOM)

    # Move to top-left
    esccmd.HVP(Point(1, 1))

    # Check relative position while still in origin mode.
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 1)

    escio.Write("X")

    # Turn off origin mode. This moves the cursor.
    esccmd.DECRESET(esccmd.DECOM)

    # Turn off scroll regions so checksum can work.
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)

    # Make sure there's an X at 5,6
    AssertScreenCharsInRectEqual(Rect(5, 6, 5, 6),
                                 [ "X" ])
