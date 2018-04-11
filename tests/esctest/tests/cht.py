import esccmd
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug, vtLevel

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

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="iTerm2 doesn't support CHT")
  # CHT is just a parameterized tab; tabs stop at the right margin...
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

    # Ensure that we can't tab out of the region
    esccmd.CHT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 30)

    # Try again, starting before the region.
    esccmd.CUP(Point(1, 9))
    esccmd.CHT(9)
    position = GetCursorPosition()
    AssertEQ(position.x(), 30)
