import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VPATests(object):
  def __init__(self, args):
    self._args = args

  def test_VPA_DefaultParams(self):
    """With no params, VPA moves to 1st line."""
    esccsi.CSI_VPA(6)

    position = GetCursorPosition()
    AssertEQ(position.y(), 6)

    esccsi.CSI_VPA()

    position = GetCursorPosition()
    AssertEQ(position.y(), 1)

  def test_VPA_StopsAtBottomEdge(self):
    """VPA won't go past the bottom edge."""
    # Position on 5th row
    esccsi.CSI_CUP(Point(6, 5))

    # Try to move 10 past the bottom edge
    size = GetScreenSize()
    esccsi.CSI_VPA(size.height() + 10)

    # Ensure at the bottom edge on same column
    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), size.height())

  def test_VPA_DoesNotChangeColumn(self):
    """VPA moves the specified line and does not change the column."""
    esccsi.CSI_CUP(Point(6, 5))
    esccsi.CSI_VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 2)

  def test_VPA_IgnoresOriginMode(self):
    """VPA does not respect origin mode."""
    # Set a scroll region.
    esccsi.CSI_DECSTBM(6, 11)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)

    # Move to center of region
    esccsi.CSI_CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.y(), 9)
    AssertEQ(position.x(), 7)

    # Turn on origin mode.
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Move to 2nd line
    esccsi.CSI_VPA(2)

    position = GetCursorPosition()
    AssertEQ(position.y(), 2)

