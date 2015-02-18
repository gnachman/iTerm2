import esccmd
from escutil import AssertEQ, GetCursorPosition, GetScreenSize
from esctypes import Point

class CUDTests(object):
  def test_CUD_DefaultParam(self):
    """CUD moves the cursor down 1 with no parameter given."""
    esccmd.CUP(Point(5, 3))
    esccmd.CUD()
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 4)

  def test_CUD_ExplicitParam(self):
    """CUD moves the cursor down by the passed-in number of lines."""
    esccmd.CUP(Point(1, 3))
    esccmd.CUD(2)
    AssertEQ(GetCursorPosition().y(), 5)

  def test_CUD_StopsAtBottomLine(self):
    """CUD moves the cursor down, stopping at the last line."""
    esccmd.CUP(Point(1, 3))
    height = GetScreenSize().height()
    esccmd.CUD(height)
    AssertEQ(GetCursorPosition().y(), height)

  def test_CUD_StopsAtBottomLineWhenBegunBelowScrollRegion(self):
    """When the cursor starts below the scroll region, CUD moves it down to the
    bottom of the screen."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccmd.DECSTBM(4, 5)

    # Position the cursor below the scroll region
    esccmd.CUP(Point(1, 6))

    # Move it down by a lot
    height = GetScreenSize().height()
    esccmd.CUD(height)

    # Ensure it stopped at the bottom of the screen
    AssertEQ(GetCursorPosition().y(), height)

  def test_CUD_StopsAtBottomMarginInScrollRegion(self):
    """When the cursor starts within the scroll region, CUD moves it down to the
    bottom margin but no farther."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccmd.DECSTBM(2, 4)

    # Position the cursor within the scroll region
    esccmd.CUP(Point(1, 3))

    # Move it up by more than the height of the scroll region
    esccmd.CUD(99)

    # Ensure it stopped at the bottom of the scroll region.
    AssertEQ(GetCursorPosition().y(), 4)

