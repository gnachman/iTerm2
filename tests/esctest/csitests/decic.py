from esc import NUL, CR, LF
import esccsi
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, AssertScreenCharsInRectEqual, knownBug, vtLevel
from esctypes import Point, Rect
import time

class DECICTests(object):
  def __init__(self, args):
    self._args = args

  def blank(self):
    if self._args.expected_terminal == "xterm":
      return ' '
    else:
      return NUL

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_DefaultParam(self):
    """ Test DECIC with default parameter """
    esccsi.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")
    esccsi.CUP(Point(2, 1))
    AssertEQ(GetCursorPosition().x(), 2)
    esccsi.DECIC()

    AssertScreenCharsInRectEqual(Rect(1, 1, 8, 2),
                                 [ "a" + self.blank() + "bcdefg",
                                   "A" + self.blank() + "BCDEFG" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_ExplicitParam(self):
    """Test DECIC with explicit parameter. Also verifies lines above and below
    the cursor are affected."""
    esccsi.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG" + CR + LF + "zyxwvut")
    esccsi.CUP(Point(2, 2))
    AssertEQ(GetCursorPosition().x(), 2)
    esccsi.DECIC(2)

    AssertScreenCharsInRectEqual(Rect(1, 1, 9, 3),
                                 [ "a" + self.blank() * 2 + "bcdefg",
                                   "A" + self.blank() * 2 + "BCDEFG",
                                   "z" + self.blank() * 2 + "yxwvut" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECIC_CursorWithinTopBottom(self):
    """DECIC should only affect rows inside region."""
    esccsi.DECSTBM()
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(1, 20)
    # Write four lines. The middle two will be in the scroll region.
    esccsi.CUP(Point(1, 1))
    escio.Write("abcdefg" + CR + LF +
                "ABCDEFG" + CR + LF +
                "zyxwvut" + CR + LF +
                "ZYXWVUT")
    # Define a scroll region. Place the cursor in it. Insert a column.
    esccsi.DECSTBM(2, 3)
    esccsi.CUP(Point(2, 2))
    esccsi.DECIC(2)

    # Remove scroll region and see if it worked.
    esccsi.DECSTBM()
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 9, 4),
                                 [ "abcdefg" + NUL * 2,
                                   "A" + self.blank() * 2 + "BCDEFG",
                                   "z" + self.blank() * 2 + "yxwvut",
                                   "ZYXWVUT" + NUL * 2 ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2",reason="Not implemented", noop=True)
  @knownBug(terminal="xterm",
            reason="xterm requires left-right mode for DECIC",
            noop=True)
  def test_DECIC_IsNoOpWhenCursorBeginsOutsideScrollRegion(self):
    """Ensure DECIC does nothing when the cursor starts out outside the scroll
    region."""
    esccsi.CUP(Point(1, 1))
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")

    # Set margin: from columns 2 to 5
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 5)

    # Position cursor outside margins
    esccsi.CUP(Point(1, 1))

    # Insert blanks
    esccsi.DECIC(10)

    # Ensure nothing happened.
    esccsi.DECRESET(esccsi.DECLRMM)
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
    esccsi.CUP(Point(startX, 1))
    escio.Write(s)
    esccsi.CUP(Point(startX, 2))
    escio.Write(s.upper())
    esccsi.CUP(Point(startX + 1, 1))
    esccsi.DECIC()

    AssertScreenCharsInRectEqual(Rect(startX, 1, width, 2),
                                 [ "a" + self.blank() + "bcdef",
                                   "A" + self.blank() + "BCDEF" ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ NUL, NUL ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECIC")
  def test_DECIC_ScrollEntirelyOffRightEdge(self):
    """Test DECIC behavior when pushing text off the right edge. """
    width = GetScreenSize().width()
    esccsi.CUP(Point(1, 1))
    escio.Write("x" * width)
    esccsi.CUP(Point(1, 2))
    escio.Write("x" * width)
    esccsi.CUP(Point(1, 1))
    esccsi.DECIC(width)

    expectedLine = self.blank() * width

    AssertScreenCharsInRectEqual(Rect(1, 1, width, 2),
                                 [ expectedLine, expectedLine ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3),
                                 [ self.blank(), self.blank() ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECIC_ScrollOffRightMarginInScrollRegion(self):
    """Test DECIC when cursor is within the scroll region."""
    esccsi.CUP(Point(1, 1))
    s = "abcdefg"
    escio.Write(s)
    esccsi.CUP(Point(1, 2))
    escio.Write(s.upper())

    # Set margin: from columns 2 to 5
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(2, 5)

    # Position cursor inside margins
    esccsi.CUP(Point(3, 1))

    # Insert blank
    esccsi.DECIC()

    # Ensure the 'e' gets dropped.
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, len(s), 2),
                                 [ "ab" + self.blank() + "cdfg",
                                   "AB" + self.blank() + "CDFG" ])


