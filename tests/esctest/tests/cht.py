import esccmd
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug

class CHTTests(object):
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  def test_CHT_OneTabStopByDefault(self):
    esccmd.CHT()
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  def test_CHT_ExplicitParameter(self):
    esccmd.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 17)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  @knownBug(terminal="xterm", reason="xterm respects scrolling regions for CHT")
  def test_CHT_IgnoresScrollingRegion(self):
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 30)

    # Move to center of region
    esccmd.CUP(Point(7, 9))

    # Ensure we can tab within the region
    esccmd.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 17)

    # Ensure that we can tab out of the region
    esccmd.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 33)

    # Try again, starting before the region.
    esccmd.CUP(Point(1, 9))
    esccmd.CHT(9)
    position = GetCursorPosition()
    AssertEQ(position.x(), 73)
