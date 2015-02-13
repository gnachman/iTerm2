import esccsi
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug

class CHTTests(object):
  def __init__(self, args):
    self._args = args

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  def test_CHT_OneTabStopByDefault(self):
    esccsi.CHT()
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  def test_CHT_ExplicitParameter(self):
    esccsi.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 17)

  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  @knownBug(terminal="xterm", reason="xterm respects scrolling regions for CHT")
  def test_CHT_IgnoresScrollingRegion(self):
    # Set a scroll region.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 30)

    # Move to center of region
    esccsi.CUP(Point(7, 9))

    # Ensure we can tab within the region
    esccsi.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 17)

    # Ensure that we can tab out of the region
    esccsi.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 33)

    # Try again, starting before the region.
    esccsi.CUP(Point(1, 9))
    esccsi.CHT(9)
    position = GetCursorPosition()
    AssertEQ(position.x(), 73)
