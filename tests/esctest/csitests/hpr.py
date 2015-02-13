from esc import NUL
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class HPRTests(object):
  def __init__(self, args):
    self._args = args

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPR_DefaultParams(self):
    """With no params, HPR moves right by 1."""
    esccsi.CUP(Point(6, 1))
    esccsi.HPR()

    position = GetCursorPosition()
    AssertEQ(position.x(), 7)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPR_StopsAtRightEdge(self):
    """HPR won't go past the right edge."""
    # Position on 6th row
    esccsi.CUP(Point(5, 6))

    # Try to move 10 past the right edge
    size = GetScreenSize()
    esccsi.HPR(size.width() + 10)

    # Ensure at the right edge on same row
    position = GetCursorPosition()
    AssertEQ(position.x(), size.width())
    AssertEQ(position.y(), 6)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPR_DoesNotChangeRow(self):
    """HPR moves the specified column and does not change the row."""
    esccsi.CUP(Point(5, 6))
    esccsi.HPR(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 6)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPR_IgnoresOriginMode(self):
    """HPR continues to work in origin mode."""
    # Set a scroll region.
    esccsi.DECSTBM(6, 11)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)

    # Enter origin mode
    esccsi.DECSET(esccsi.DECOM)

    # Move to center of region
    esccsi.CUP(Point(2, 2))
    escio.Write('X')

    # Move right by 2
    esccsi.HPR(2)
    escio.Write('Y')

    # Exit origin mode
    esccsi.DECRESET(esccsi.DECOM)

    # Reset margins
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSTBM()

    # See what happened
    AssertScreenCharsInRectEqual(Rect(5, 7, 9, 7), [ NUL + "X" + NUL * 2 + "Y" ])
