import esccmd
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point

class CUFTests(object):
  def test_CUF_DefaultParam(self):
    """CUF moves the cursor right 1 with no parameter given."""
    esccmd.CUP(Point(5, 3))
    esccmd.CUF()
    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

  def test_CUF_ExplicitParam(self):
    """CUF moves the cursor right by the passed-in number of lines."""
    esccmd.CUP(Point(1, 2))
    esccmd.CUF(2)
    AssertEQ(GetCursorPosition().x(), 3)

  def test_CUF_StopsAtRightSide(self):
    """CUF moves the cursor right, stopping at the last line."""
    esccmd.CUP(Point(1, 3))
    width = GetScreenSize().width()
    esccmd.CUF(width)
    AssertEQ(GetCursorPosition().x(), width)

  def test_CUF_StopsAtRightEdgeWhenBegunRightOfScrollRegion(self):
    """When the cursor starts right of the scroll region, CUF moves it right to the
    edge of the screen."""
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Position the cursor right of the scroll region
    esccmd.CUP(Point(12, 3))
    AssertEQ(GetCursorPosition().x(), 12)

    # Move it right by a lot
    width = GetScreenSize().width()
    esccmd.CUF(width)

    # Ensure it stopped at the right edge of the screen
    AssertEQ(GetCursorPosition().x(), width)

  def test_CUF_StopsAtRightMarginInScrollRegion(self):
    """When the cursor starts within the scroll region, CUF moves it right to the
    right margin but no farther."""
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    # Position the cursor inside the scroll region
    esccmd.CUP(Point(7, 3))

    # Move it right by a lot
    width = GetScreenSize().width()
    esccmd.CUF(width)

    # Ensure it stopped at the right edge of the screen
    AssertEQ(GetCursorPosition().x(), 10)
