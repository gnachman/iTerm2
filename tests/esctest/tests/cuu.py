import esccmd
from escutil import AssertEQ, GetCursorPosition
from esctypes import Point

class CUUTests(object):
  def test_CUU_DefaultParam(self):
    """CUU moves the cursor up 1 with no parameter given."""
    esccmd.CUP(Point(5, 3))
    esccmd.CUU()
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 2)

  def test_CUU_ExplicitParam(self):
    """CUU moves the cursor up by the passed-in number of lines."""
    esccmd.CUP(Point(1, 3))
    esccmd.CUU(2)
    AssertEQ(GetCursorPosition().y(), 1)

  def test_CUU_StopsAtTopLine(self):
    """CUU moves the cursor up, stopping at the first line."""
    esccmd.CUP(Point(1, 3))
    esccmd.CUU(99)
    AssertEQ(GetCursorPosition().y(), 1)

  def test_CUU_StopsAtTopLineWhenBegunAboveScrollRegion(self):
    """When the cursor starts above the scroll region, CUU moves it up to the
    top of the screen."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccmd.DECSTBM(4, 5)

    # Position the cursor above the scroll region
    esccmd.CUP(Point(1, 3))

    # Move it up by a lot
    esccmd.CUU(99)

    # Ensure it stopped at the top of the screen
    AssertEQ(GetCursorPosition().y(), 1)

  def test_CUU_StopsAtTopMarginInScrollRegion(self):
    """When the cursor starts within the scroll region, CUU moves it up to the
    top margin but no farther."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccmd.DECSTBM(2, 4)

    # Position the cursor within the scroll region
    esccmd.CUP(Point(1, 3))

    # Move it up by more than the height of the scroll region
    esccmd.CUU(99)

    # Ensure it stopped at the top of the scroll region.
    AssertEQ(GetCursorPosition().y(), 2)
