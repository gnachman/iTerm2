import esc
import esccsi
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class CRTests(object):
  def test_CR_Basic(self):
    esccsi.CUP(Point(3, 3))
    escio.Write(esc.CR)
    AssertEQ(GetCursorPosition(), Point(1, 3))

  def test_CR_MovesToLeftMarginWhenRightOfLeftMargin(self):
    """Move the cursor to the left margin if it starts right of it."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.CUP(Point(6, 1))
    escio.Write(esc.CR)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  @knownBug(terminal="iTerm2",
            reason="iTerm2 incorrectly moves to the left margin.")
  def test_CR_MovesToLeftOfScreenWhenLeftOfLeftMargin(self):
    """Move the cursor to the left edge of the screen when it starts of left the margin."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.CUP(Point(4, 1))
    escio.Write(esc.CR)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_CR_MovesToLeftMarginWhenLeftOfLeftMarginInOriginMode(self):
    """In origin mode, always go to the left margin, even if the cursor starts left of it."""
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.DECSET(esccsi.DECOM)
    esccsi.CUP(Point(4, 1))
    escio.Write(esc.CR)
    esccsi.DECRESET(esccsi.DECLRMM)
    escio.Write("x")
    esccsi.DECRESET(esccsi.DECOM)
    AssertScreenCharsInRectEqual(Rect(5, 1, 5, 1), [ "x" ])

