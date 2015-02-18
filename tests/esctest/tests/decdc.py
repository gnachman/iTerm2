from esc import NUL, CR, LF
import escargs
import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, AssertScreenCharsInRectEqual, knownBug, vtLevel
from esctypes import Point, Rect
import time

class DECDCTests(object):
  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECDC")
  def test_DECDC_DefaultParam(self):
    """Test DECDC with default parameter """
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")
    esccmd.CUP(Point(2, 1))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.DECDC()

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 2),
                                 [ "acdefg" + NUL,
                                   "ACDEFG" + NUL ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECDC")
  def test_DECDC_ExplicitParam(self):
    """Test DECDC with explicit parameter. Also verifies lines above and below
    the cursor are affected."""
    esccmd.CUP(Point(1, 1))
    AssertEQ(GetCursorPosition().x(), 1)
    escio.Write("abcdefg" + CR + LF + "ABCDEFG" + CR + LF + "zyxwvut")
    esccmd.CUP(Point(2, 2))
    AssertEQ(GetCursorPosition().x(), 2)
    esccmd.DECDC(2)

    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 3),
                                 [ "adefg" + NUL * 2,
                                   "ADEFG" + NUL * 2,
                                   "zwvut" + NUL * 2 ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECDC_CursorWithinTopBottom(self):
    """DECDC should only affect rows inside region."""
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
    esccmd.DECDC(2)

    # Remove scroll region and see if it worked.
    esccmd.DECSTBM()
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 4),
                                 [ "abcdefg",
                                   "ADEFG" + NUL * 2,
                                   "zwvut" + NUL * 2,
                                   "ZYXWVUT" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2",reason="Not implemented", noop=True)
  @knownBug(terminal="xterm",
            reason="xterm requires left-right mode for DECDC",
            noop=True)
  def test_DECDC_IsNoOpWhenCursorBeginsOutsideScrollRegion(self):
    """Ensure DECDC does nothing when the cursor starts out outside the scroll
    region."""
    esccmd.CUP(Point(1, 1))
    escio.Write("abcdefg" + CR + LF + "ABCDEFG")

    # Set margin: from columns 2 to 5
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(2, 5)

    # Position cursor outside margins
    esccmd.CUP(Point(1, 1))

    # Insert blanks
    esccmd.DECDC(10)

    # Ensure nothing happened.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 2),
                                 [ "abcdefg",
                                   "ABCDEFG" ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  @knownBug(terminal="xterm", reason="xterm requires left-right mode for DECDC")
  def test_DECDC_DeleteAll(self):
    """Test DECDC behavior when deleting more columns than are available."""
    width = GetScreenSize().width()
    s = "abcdefg"
    startX = width - len(s) + 1
    esccmd.CUP(Point(startX, 1))
    escio.Write(s)
    esccmd.CUP(Point(startX, 2))
    escio.Write(s.upper())
    esccmd.CUP(Point(startX + 1, 1))
    esccmd.DECDC(width + 10)

    AssertScreenCharsInRectEqual(Rect(startX, 1, width, 2),
                                 [ "a" + NUL * 6,
                                   "A" + NUL * 6 ])
    # Ensure there is no wrap-around.
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 3), [ NUL, NUL ])

  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECDC_DeleteWithLeftRightMargins(self):
    """Test DECDC when cursor is within the scroll region."""
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
    esccmd.DECDC()

    # Ensure the 'e' gets dropped.
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 2),
                                 [ "abde" + NUL + "fg",
                                   "ABDE" + NUL + "FG" ])


  @vtLevel(4)
  @knownBug(terminal="iTerm2", reason="Not implemented")
  def test_DECDC_DeleteAllWithLeftRightMargins(self):
    """Test DECDC when cursor is within the scroll region."""
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
    esccmd.DECDC(99)

    esccmd.DECRESET(esccmd.DECLRMM)
    AssertScreenCharsInRectEqual(Rect(1, 1, 7, 2),
                                 [ "ab" + NUL * 3 + "fg",
                                   "AB" + NUL * 3 + "FG" ])


