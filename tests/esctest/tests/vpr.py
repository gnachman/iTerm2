from esc import NUL
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VPRTests(object):
  def test_VPR_DefaultParams(self):
    """With no params, VPR moves right by 1."""
    esccmd.CUP(Point(1, 6))
    esccmd.VPR()

    position = GetCursorPosition()
    AssertEQ(position.y(), 7)

  def test_VPR_StopsAtBottomEdge(self):
    """VPR won't go past the bottom edge."""
    # Position on 5th column
    esccmd.CUP(Point(5, 6))

    # Try to move 10 past the bottom edge
    size = GetScreenSize()
    esccmd.VPR(size.height() + 10)

    # Ensure at the bottom edge on same column
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), size.height())

  def test_VPR_DoesNotChangeColumn(self):
    """VPR moves the specified row and does not change the column."""
    esccmd.CUP(Point(5, 6))
    esccmd.VPR(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 8)

  def test_VPR_IgnoresOriginMode(self):
    """VPR continues to work in origin mode."""
    # Set a scroll region.
    esccmd.DECSTBM(6, 11)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Enter origin mode
    esccmd.DECSET(esccmd.DECOM)

    # Move to center of region
    esccmd.CUP(Point(2, 2))
    escio.Write('X')

    # Move down by 2
    esccmd.VPR(2)
    escio.Write('Y')

    # Exit origin mode
    esccmd.DECRESET(esccmd.DECOM)

    # Reset margins
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSTBM()

    # See what happened
    AssertScreenCharsInRectEqual(Rect(6, 7, 7, 9), [ 'X' + NUL,
                                                      NUL * 2,
                                                      NUL + 'Y' ])

