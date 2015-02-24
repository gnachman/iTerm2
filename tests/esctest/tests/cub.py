import esccmd
from escutil import AssertEQ, GetCursorPosition, knownBug
from esctypes import Point

class CUBTests(object):
  def test_CUB_DefaultParam(self):
    """CUB moves the cursor left 1 with no parameter given."""
    esccmd.CUP(Point(5, 3))
    esccmd.CUB()
    position = GetCursorPosition()
    AssertEQ(position.x(), 4)
    AssertEQ(position.y(), 3)

  def test_CUB_ExplicitParam(self):
    """CUB moves the cursor left by the passed-in number of columns."""
    esccmd.CUP(Point(5, 4))
    esccmd.CUB(2)
    AssertEQ(GetCursorPosition().x(), 3)

  def test_CUB_StopsAtLeftEdge(self):
    """CUB moves the cursor left, stopping at the first column."""
    esccmd.CUP(Point(5, 3))
    esccmd.CUB(99)
    AssertEQ(GetCursorPosition().x(), 1)

  def test_CUB_StopsAtLeftEdgeWhenBegunLeftOfScrollRegion(self):
    """When the cursor starts left of the scroll region, CUB moves it left to the
    left edge of the screen."""
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Position the cursor left of the scroll region
    esccmd.CUP(Point(4, 3))

    # Move it left by a lot
    esccmd.CUB(99)

    # Ensure it stopped at the left edge of the screen
    AssertEQ(GetCursorPosition().x(), 1)

  def test_CUB_StopsAtLeftMarginInScrollRegion(self):
    """When the cursor starts within the scroll region, CUB moves it left to the
    left margin but no farther."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Position the cursor within the scroll region
    esccmd.CUP(Point(7, 3))

    # Move it left by more than the height of the scroll region
    esccmd.CUB(99)

    # Ensure it stopped at the top of the scroll region.
    AssertEQ(GetCursorPosition().x(), 5)

