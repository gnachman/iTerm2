from esc import NUL, CR, LF, blank
import escargs
import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, AssertScreenCharsInRectEqual, knownBug, vtLevel
from esctypes import Point, Rect
import time

class DECICTests(object):

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_DefaultParam(self):
    """ Test DECIC with default parameter """
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")
    esccmd.CUP(Point(2, 1))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.DECIC()

    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 2),
                                 [ "a" + blank() + "bcdefg",
                                   "A" + blank() + "BCDEFG" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_ExplicitParam(self):
    """Test DECIC with explicit parameter. Also verifies lines above and below
    the cursor are affected."""
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG" + CR + LF + "zyxwvut")
    esccmd.CUP(Point(2, 2))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.DECIC(2)

    AssertScreenCharsInRectEqual(Rect(1, 1, 9, 3),
                                 [ "a" + blank() * 2 + "bcdefg",
                                   "A" + blank() * 2 + "BCDEFG",
                                   "z" + blank() * 2 + "yxwvut" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECIC_CursorWithinTopBottom(self):
    """DECIC should only affect rows inside region."""
    esccmd.DECSTBM()
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(1, 20)
    # Write four lines. The middle two will be in the scroll region.
    esccmd.CUP(Point(1, 1))
    escio.Write("abcdefg" + CR + LF +
                "ABCDEFG" + CR + LF +
                "zyxwvut" + CR + LF +
                "ZYXWVUT")
    # Define a scroll region. Place the cursor in it. Insert a column.
    esccmd.DECSTBM(2, 3)
    esccmd.CUP(Point(2, 2))
    esccmd.DECIC(2)

    # Remove scroll region and see if it worked.
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 9, 4),
                                 [ "abcdefg" + NUL * 2,
                                   "A" + blank() * 2 + "BCDEFG",
                                   "z" + blank() * 2 + "yxwvut",
                                   "ZYXWVUT" + NUL * 2 ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2",reason="Not implemented", noop=True)
  @knownBug(terminal="xterm",
            reason="xterm requires left-right mode for DECIC",
            noop=True)
  def test_DECIC_IsNoOpWhenCursorBeginsOutsideScrollRegion(self):
    """Ensure DECIC does nothing when the cursor starts out outside the scroll
    region."""
    esccmd.CUP(Point(1, 1))
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")

    # Set margin: from columns 2 to 5
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 5)

    # Position cursor outside margins
    esccmd.CUP(Point(1, 1))

    # Insert blanks
    esccmd.DECIC(10)

    # Ensure nothing happened.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 2),
                                 [ "abcdefg",
                                   "ABCDEFG" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_ScrollOffRightEdge(self):
    """Test DECIC behavior when pushing text off the right edge. """
    width = GetScreenSize().width()
    s = "abcdefg"
    startX = width - len(s) + 1
    esccmd.CUP(Point(startX, 1))
    escio.Write(s)
    esccmd.CUP(Point(startX, 2))
    escio.Write(s.upper())
    esccmd.CUP(Point(startX + 1, 1))
    esccmd.DECIC()

    AssertScreenCharsInRectEqual(Rect(startX, 1, width, 2),
                                 [ "a" + blank() + "bcdef",
                                   "A" + blank() + "BCDEF" ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ NUL, NUL ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_ScrollEntirelyOffRightEdge(self):
    """Test DECIC behavior when pushing text off the right edge. """
    width = GetScreenSize().width()
    esccmd.CUP(Point(1, 1))
    escio.Write("x" * width)
    esccmd.CUP(Point(1, 2))
    escio.Write("x" * width)
    esccmd.CUP(Point(1, 1))
    esccmd.DECIC(width)

    expectedLine = blank() * width

    AssertScreenCharsInRectEqual(Rect(1, 1, width, 2),
                                 [ expectedLine, expectedLine ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3),
                                 [ blank(), blank() ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECIC_ScrollOffRightMarginInScrollRegion(self):
    """Test DECIC when cursor is within the scroll region."""
    esccmd.CUP(Point(1, 1))
    s = "abcdefg"
    escio.Write(s)
    esccmd.CUP(Point(1, 2))
    escio.Write(s.upper())

    # Set margin: from columns 2 to 5
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 5)

    # Position cursor inside margins
    esccmd.CUP(Point(3, 1))

    # Insert blank
    esccmd.DECIC()

    # Ensure the 'e' gets dropped.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, len(s), 2),
                                 [ "ab" + blank() + "cdfg",
                                   "AB" + blank() + "CDFG" ])


