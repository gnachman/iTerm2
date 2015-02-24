import esc
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class CRTests(object):
  def test_CR_Basic(self):
    esccmd.CUP(Point(3, 3))
    escio.Write(esc.CR)
    AssertEQ(GetCursorPosition(), Point(1, 3))

  def test_CR_MovesToLeftMarginWhenRightOfLeftMargin(self):
    """Move the cursor to the left margin if it starts right of it."""
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(6, 1))
    escio.Write(esc.CR)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  def test_CR_MovesToLeftOfScreenWhenLeftOfLeftMargin(self):
    """Move the cursor to the left edge of the screen when it starts of left the margin."""
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(4, 1))
    escio.Write(esc.CR)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_CR_StaysPutWhenAtLeftMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 1))
    escio.Write(esc.CR)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  def test_CR_MovesToLeftMarginWhenLeftOfLeftMarginInOriginMode(self):
    """In origin mode, always go to the left margin, even if the cursor starts left of it."""
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.DECSET(esccmd.DECOM)
    esccmd.CUP(Point(4, 1))
    escio.Write(esc.CR)
    esccmd.DECRESET(esccmd.DECLRMM)
    escio.Write("x")
    esccmd.DECRESET(esccmd.DECOM)
    AssertScreenCharsInRectEqual(Rect(5, 1, 5, 1), [ "x" ])

