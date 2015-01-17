from esc import NUL
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VPRTests(object):
  def __init__(self, args):
    self._args = args

  def test_VPR_DefaultParams(self):
    """With no params, VPR moves right by 1."""
    esccsi.CSI_CUP(Point(1, 6))
    esccsi.CSI_VPR()

    position = GetCursorPosition()
    AssertEQ(position.y(), 7)

  def test_VPR_StopsAtBottomEdge(self):
    """VPR won't go past the bottom edge."""
    # Position on 5th column
    esccsi.CSI_CUP(Point(5, 6))

    # Try to move 10 past the bottom edge
    size = GetScreenSize()
    esccsi.CSI_VPR(size.height() + 10)

    # Ensure at the bottom edge on same column
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), size.height())

  def test_VPR_DoesNotChangeColumn(self):
    """VPR moves the specified row and does not change the column."""
    esccsi.CSI_CUP(Point(5, 6))
    esccsi.CSI_VPR(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 8)

  def test_VPR_IgnoresOriginMode(self):
    """VPR continues to work in origin mode."""
    # Set a scroll region.
    esccsi.CSI_DECSTBM(6, 11)
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)

    # Enter origin mode
    esccsi.CSI_DECSET(esccsi.DECOM)

    # Move to center of region
    esccsi.CSI_CUP(Point(2, 2))
    escio.Write('X')

    # Move down by 2
    esccsi.CSI_VPR(2)
    escio.Write('Y')

    # Exit origin mode
    esccsi.CSI_DECRESET(esccsi.DECOM)

    # Reset margins
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSTBM()

    # See what happened
    AssertScreenCharsInRectEqual(Rect(6, 7, 7, 9), [ 'X' + NUL,
                                                      NUL * 2,
                                                      NUL + 'Y' ])

