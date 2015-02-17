from esc import NUL, S7C1T, S8C1T
import escargs
import escc1
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, optionRequired
from esctypes import Point, Rect

class INDTests(object):
  def test_IND_Basic(self):
    """Index moves the cursor down one line."""
    esccsi.CUP(Point(5, 3))
    escc1.IND()
    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 4)

  def test_IND_Scrolls(self):
    """Index scrolls when it hits the bottom."""
    height = GetScreenSize().height()

    # Put a and b on the last two lines.
    esccsi.CUP(Point(2, height - 1))
    escio.Write("a")
    esccsi.CUP(Point(2, height))
    escio.Write("b")

    # Move to penultimate line.
    esccsi.CUP(Point(2, height - 1))

    # Move down, ensure no scroll yet.
    escc1.IND()
    AssertEQ(GetCursorPosition().y(), height)
    AssertScreenCharsInRectEqual(Rect(2, height - 2, 2, height), [ NUL, "a", "b" ])

    # Move down, ensure scroll.
    escc1.IND()
    AssertEQ(GetCursorPosition().y(), height)
    AssertScreenCharsInRectEqual(Rect(2, height - 2, 2, height), [ "a", "b", NUL ])

  def test_IND_ScrollsInTopBottomRegionStartingAbove(self):
    """Index scrolls when it hits the bottom region (starting above top)."""
    esccsi.DECSTBM(4, 5)
    esccsi.CUP(Point(2, 5))
    escio.Write("x")

    esccsi.CUP(Point(2, 3))
    escc1.IND()  # To 4
    escc1.IND()  # To 5
    escc1.IND()  # Stay at 5 and scroll x up one line
    AssertEQ(GetCursorPosition(), Point(2, 5))
    AssertScreenCharsInRectEqual(Rect(2, 4, 2, 5), [ "x", NUL ])

  def test_IND_ScrollsInTopBottomRegionStartingWithin(self):
    """Index scrolls when it hits the bottom region (starting within region)."""
    esccsi.DECSTBM(4, 5)
    esccsi.CUP(Point(2, 5))
    escio.Write("x")

    esccsi.CUP(Point(2, 4))
    escc1.IND()  # To 5
    escc1.IND()  # Stay at 5 and scroll x up one line
    AssertEQ(GetCursorPosition(), Point(2, 5))
    AssertScreenCharsInRectEqual(Rect(2, 4, 2, 5), [ "x", NUL ])

  @knownBug(terminal="iTerm2",
            reason="iTerm2 improperly scrolls when the cursor is outside the left-right region.")
  def test_IND_MovesDoesNotScrollOutsideLeftRight(self):
    """Cursor moves down but won't scroll when outside left-right region."""
    esccsi.DECSTBM(2, 5)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 5)
    esccsi.CUP(Point(3, 5))
    escio.Write("x")

    # Move past bottom margin but to the right of the left-right region
    esccsi.CUP(Point(6, 5))
    escc1.IND()
    # Cursor won't pass bottom or scroll.
    AssertEQ(GetCursorPosition(), Point(6, 5))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Try to move past the bottom of the screen but to the right of the left-right region
    height = GetScreenSize().height()
    esccsi.CUP(Point(6, height))
    escc1.IND()
    AssertEQ(GetCursorPosition(), Point(6, height))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Move past bottom margin but to the left of the left-right region
    esccsi.CUP(Point(1, 5))
    escc1.IND()
    AssertEQ(GetCursorPosition(), Point(1, 5))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

    # Try to move past the bottom of the screen but to the left of the left-right region
    height = GetScreenSize().height()
    esccsi.CUP(Point(1, height))
    escc1.IND()
    AssertEQ(GetCursorPosition(), Point(1, height))
    AssertScreenCharsInRectEqual(Rect(3, 5, 3, 5), [ "x" ])

  def test_IND_StopsAtBottomLineWhenBegunBelowScrollRegion(self):
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
      escc1.IND()

    # Ensure it stopped at the bottom of the screen
    AssertEQ(GetCursorPosition().y(), height)

    # Ensure no scroll
    AssertScreenCharsInRectEqual(Rect(1, 6, 1, 6), [ "x" ])

  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  def test_IND_8bit(self):
    esccsi.CUP(Point(5, 3))

    escio.use8BitControls = True
    escio.Write(S8C1T)
    escc1.IND()
    escio.Write(S7C1T)
    escio.use8BitControls = False

    position = GetCursorPosition()
    AssertEQ(position.x(), 5)
    AssertEQ(position.y(), 4)
