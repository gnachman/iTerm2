import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class HPATests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPA_DefaultParams(self):
    """With no params, HPA moves to 1st column."""
    esccmd.HPA(6)

    position = GetCursorPosition()
    AssertEQ(position.x(), 6)

    esccmd.HPA()

    position = GetCursorPosition()
    AssertEQ(position.x(), 1)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPA_StopsAtRightEdge(self):
    """HPA won't go past the right edge."""
    # Position on 6th row
    esccmd.CUP(Point(5, 6))

    # Try to move 10 past the right edge
    size = GetScreenSize()
    esccmd.HPA(size.width() + 10)

    # Ensure at the right edge on same row
    position = GetCursorPosition()
    AssertEQ(position.x(), size.width())
    AssertEQ(position.y(), 6)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPA_DoesNotChangeRow(self):
    """HPA moves the specified column and does not change the row."""
    esccmd.CUP(Point(5, 6))
    esccmd.HPA(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 2)
    AssertEQ(position.y(), 6)

  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_HPA_IgnoresOriginMode(self):
    """HPA does not respect origin mode."""
    # Set a scroll region.
    esccmd.DECSTBM(6, 11)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Move to center of region
    esccmd.CUP(Point(7, 9))
    position = GetCursorPosition()
    AssertEQ(position.x(), 7)
    AssertEQ(position.y(), 9)

    # Turn on origin mode.
    esccmd.DECSET(esccmd.DECOM)

    # Move to 2nd column
    esccmd.HPA(2)

    position = GetCursorPosition()
    AssertEQ(position.x(), 2)
