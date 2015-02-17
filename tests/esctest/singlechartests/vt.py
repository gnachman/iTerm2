from esc import VT, NUL
import escc1
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class VTTests(object):
  """LNM is tested in the SM tests, and not duplicated here. These tests are
  the same as those for IND."""
  def test_VT_Basic(self):
    """VT moves the cursor down one line."""
    esccsi.CUP(Point(5, 3))
    escio.Write(VT)
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 4)

  def test_VT_Scrolls(self):
    """VT scrolls when it hits the bottom."""
    height = GetScreenSize().height()

    # Put a and b on the last two lines.
    esccsi.CUP(Point(2, height - 1))
    escio.Write("a")
    esccsi.CUP(Point(2, height))
    escio.Write("b")

    # Move to penultimate line.
    esccsi.CUP(Point(2, height - 1))

    # Move down, ensure no scroll yet.
    escio.Write(VT)
    AssertEQ(GetCursorPosition().y(), height)
    AssertScreenCharsInRectEqual(Rect(2, height - 2, 2, height), [ NUL, "a", "b" ])

    # Move down, ensure scroll.
    escio.Write(VT)
    AssertEQ(GetCursorPosition().y(), height)
    AssertScreenCharsInRectEqual(Rect(2, height - 2, 2, height), [ "a", "b", NUL ])

  def test_VT_ScrollsInTopBottomRegionStartingAbove(self):
    """VT scrolls when it hits the bottom region (starting above top)."""
    esccsi.DECSTBM(4, 5)
    esccsi.CUP(Point(2, 5))
    escio.Write("x")

    esccsi.CUP(Point(2, 3))
    escio.Write(VT)
    escio.Write(VT)
    escio.Write(VT)
    AssertEQ(GetCursorPosition(), Point(2, 5))
    AssertScreenCharsInRectEqual(Rect(2, 4, 2, 5), [ "x", NUL ])

  def test_VT_ScrollsInTopBottomRegionStartingWithin(self):
    """VT scrolls when it hits the bottom region (starting within region)."""
    esccsi.DECSTBM(4, 5)
    esccsi.CUP(Point(2, 5))
    escio.Write("x")

    esccsi.CUP(Point(2, 4))
    escio.Write(VT)
    escio.Write(VT)
    AssertEQ(GetCursorPosition(), Point(2, 5))
    AssertScreenCharsInRectEqual(Rect(2, 4, 2, 5), [ "x", NUL ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 improperly scrolls when the cursor is outside the left-right region.")
  def test_VT_MovesDoesNotScrollOutsideLeftRight(self):
    """Cursor moves down but won't scroll when outside left-right region."""
    esccsi.DECSTBM(2, 5)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 5)
    esccsi.CUP(Point(3, 5))
    escio.Write("x")

    # Move past bottom margin but to the right of the left-right region
    esccsi.CUP(Point(6, 5))
    escio.Write(VT)
    # Cursor won't pass bottom or scroll.
    AssertEQ(GetCursorPosition(), Point(6, 5))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Try to move past the bottom of the screen but to the right of the left-right region
    height = GetScreenSize().height()
    esccsi.CUP(Point(6, height))
    escio.Write(VT)
    AssertEQ(GetCursorPosition(), Point(6, height))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Move past bottom margin but to the left of the left-right region
    esccsi.CUP(Point(1, 5))
    escio.Write(VT)
    AssertEQ(GetCursorPosition(), Point(1, 5))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Try to move past the bottom of the screen but to the left of the left-right region
    height = GetScreenSize().height()
    esccsi.CUP(Point(1, height))
    escio.Write(VT)
    AssertEQ(GetCursorPosition(), Point(1, height))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

  def test_VT_StopsAtBottomLineWhenBegunBelowScrollRegion(self):
    """When the cursor starts below the scroll region, index moves it down to the
    bottom of the screen but won't scroll."""
    # Set a scroll region. This must be done first because DECSTBM moves the cursor to the origin.
    esccsi.DECSTBM(4, 5)

    # Position the cursor below the scroll region
    esccsi.CUP(Point(1, 6))
    escio.Write("x")

    # Move it down by a lot
    height = GetScreenSize().height()
    for i in xrange(height):
      escio.Write(VT)

    # Ensure it stopped at the bottom of the screen
    AssertEQ(GetCursorPosition().y(), height)

    # Ensure no scroll
    AssertScreenCharsInRectEqual(Rect(1, 6, 1, 6), [ "x" ])
