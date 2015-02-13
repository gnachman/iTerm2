import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VPATests(object):
  def __init__(self, args):
    self._args = args

  def test_VPA_DefaultParams(self):
    """With no params, VPA moves to 1st line."""
    esccsi.VPA(6)

    position = GetCursorPosition()
    AssertEQ(position.y(), 6)

    esccsi.VPA()

    position = GetCursorPosition()
    AssertEQ(position.y(), 1)

  def test_VPA_StopsAtBottomEdge(self):
    """VPA won't go past the bottom edge."""
    # Position on 5th row
    esccsi.CUP(Point(6, 5))

    # Try to move 10 past the bottom edge
    size = GetScreenSize()
    esccsi.VPA(size.height() + 10)

    # Ensure at the bottom edge on same column
    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), size.height())

  def test_VPA_DoesNotChangeColumn(self):
    """VPA moves the specified line and does not change the column."""
    esccsi.CUP(Point(6, 5))
    esccsi.VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 2)

  def test_VPA_IgnoresOriginMode(self):
    """VPA does not respect origin mode."""
    # Set a scroll region.
    esccsi.DECSTBM(6, 11)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)

    # Move to center of region
    esccsi.CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.y(), 9)
    AssertEQ(position.x(), 7)

    # Turn on origin mode.
    esccsi.DECSET(esccsi.DECOM)

    # Move to 2nd line
    esccsi.VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.y(), 2)

