import esccsi
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point

class CUFTests(object):
  def test_CUF_DefaultParam(self):
    """CUF moves the cursor right 1 with no parameter given."""
    esccsi.CUP(Point(5, 3))
    esccsi.CUF()
    position = GetCursorPosition()
    AssertEQ(position.x(), 6)
    AssertEQ(position.y(), 3)

  def test_CUF_ExplicitParam(self):
    """CUF moves the cursor right by the passed-in number of lines."""
    esccsi.CUP(Point(1, 2))
    esccsi.CUF(2)
    AssertEQ(GetCursorPosition().x(), 3)

  def test_CUF_StopsAtRightSide(self):
    """CUF moves the cursor right, stopping at the last line."""
    esccsi.CUP(Point(1, 3))
    width = GetScreenSize().width()
    esccsi.CUF(width)
    AssertEQ(GetCursorPosition().x(), width)

  @knownBug(terminal="iTerm2",
            reason="iTerm2 should stop cursor at the right margin when doing CUF inside a scroll region, but it allows it to exit the region.")
  def test_CUF_StopsAtRightEdgeWhenBegunRightOfScrollRegion(self):
    """When the cursor starts right of the scroll region, CUF moves it right to the
    edge of the screen."""
    # Set a scroll region.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)

    # Position the cursor right of the scroll region
    esccsi.CUP(Point(12, 3))
    AssertEQ(GetCursorPosition().x(), 12)

    # Move it right by a lot
    width = GetScreenSize().width()
    esccsi.CUF(width)

    # Ensure it stopped at the right edge of the screen
    AssertEQ(GetCursorPosition().x(), width)

  def test_CUF_StopsAtRightMarginInScrollRegion(self):
    """When the cursor starts within the scroll region, CUF moves it right to the
    right margin but no farther."""
    # Set a scroll region.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)

    # Position the cursor inside the scroll region
    esccsi.CUP(Point(7, 3))

    # Move it right by a lot
    width = GetScreenSize().width()
    esccsi.CUF(width)

    # Ensure it stopped at the right edge of the screen
    AssertEQ(GetCursorPosition().x(), 10)
