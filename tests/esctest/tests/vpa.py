import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VPATests(object):
  def test_VPA_DefaultParams(self):
    """With no params, VPA moves to 1st line."""
    esccmd.VPA(6)

    position = GetCursorPosition()
    AssertEQ(position.y(), 6)

    esccmd.VPA()

    position = GetCursorPosition()
    AssertEQ(position.y(), 1)

  def test_VPA_StopsAtBottomEdge(self):
    """VPA won't go past the bottom edge."""
    # Position on 5th row
    esccmd.CUP(Point(6, 5))

    # Try to move 10 past the bottom edge
    size = GetScreenSize()
    esccmd.VPA(size.height() + 10)

    # Ensure at the bottom edge on same column
    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), size.height())

  def test_VPA_DoesNotChangeColumn(self):
    """VPA moves the specified line and does not change the column."""
    esccmd.CUP(Point(6, 5))
    esccmd.VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 2)

  def test_VPA_IgnoresOriginMode(self):
    """VPA does not respect origin mode."""
    # Set a scroll region.
    esccmd.DECSTBM(6, 11)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Move to center of region
    esccmd.CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.y(), 9)
    AssertEQ(position.x(), 7)

    # Turn on origin mode.
    esccmd.DECSET(esccmd.DECOM)

    # Move to 2nd line
    esccmd.VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.y(), 2)

