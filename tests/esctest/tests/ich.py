from esc import NUL, blank
import escargs
import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, AssertScreenCharsInRectEqual, knownBug
from esctypes import Point, Rect

class ICHTests(object):
  def test_ICH_DefaultParam(self):
    """ Test ICH with default parameter """
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg")
    esccmd.CUP(Point(2, 1))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.ICH()

    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 1),
                                 [ "a" + blank() + "bcdefg" ])

  def test_ICH_ExplicitParam(self):
    """Test ICH with explicit parameter. """
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg")
    esccmd.CUP(Point(2, 1))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.ICH(2)

    AssertScreenCharsInRectEqual(Rect(1, 1, 9, 1),
                                 [ "a" + blank() + blank() + "bcdefg"])

  def test_ICH_IsNoOpWhenCursorBeginsOutsideScrollRegion(self):
    """Ensure ICH does nothing when the cursor starts out outside the scroll region."""
    esccmd.CUP(Point(1, 1))
    s = "abcdefg"
    escio.Write(s)

    # Set margin: from columns 2 to 5
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 5)

    # Position cursor outside margins
    esccmd.CUP(Point(1, 1))

    # Insert blanks
    esccmd.ICH(10)

    # Ensure nothing happened.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, len(s), 1),
                                 [ s ])

  def test_ICH_ScrollOffRightEdge(self):
    """Test ICH behavior when pushing text off the right edge. """
    width = GetScreenSize().width()
    s = "abcdefg"
    startX = width - len(s) + 1
    esccmd.CUP(Point(startX, 1))
    escio.Write(s)
    esccmd.CUP(Point(startX + 1, 1))
    esccmd.ICH()

    AssertScreenCharsInRectEqual(Rect(startX, 1, width, 1),
                                 [ "a" + blank() + "bcdef" ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])

  @knownBug(terminal="xterm", reason="Asserts", shouldTry=False)
  def test_ICH_ScrollEntirelyOffRightEdge(self):
    """Test ICH behavior when pushing text off the right edge. """
    width = GetScreenSize().width()
    esccmd.CUP(Point(1, 1))
    escio.Write("x" * width)
    esccmd.CUP(Point(1, 1))
    esccmd.ICH(width)

    expectedLine = blank() * width

    AssertScreenCharsInRectEqual(Rect(1, 1, width, 1),
                                 [ expectedLine ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])

  def test_ICH_ScrollOffRightMarginInScrollRegion(self):
    """Test ICH when cursor is within the scroll region."""
    esccmd.CUP(Point(1, 1))
    s = "abcdefg"
    escio.Write(s)

    # Set margin: from columns 2 to 5
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 5)

    # Position cursor inside margins
    esccmd.CUP(Point(3, 1))

    # Insert blank
    esccmd.ICH()

    # Ensure the 'e' gets dropped.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, len(s), 1),
                                 [ "ab" + blank() + "cdfg" ])

