import esc
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class BSTests(object):
  def test_BS_Basic(self):
    esccmd.CUP(Point(3, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(2, 3))

  def test_BS_NoWrapByDefault(self):
    esccmd.CUP(Point(1, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 3))

  def test_BS_WrapsInWraparoundMode(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.CUP(Point(1, 3))
    escio.Write(esc.BS)
    size = GetScreenSize()
    AssertEQ(GetCursorPosition(), Point(size.width(), 2))

  def test_BS_ReverseWrapRequiresDECAWM(self):
    esccmd.DECRESET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.CUP(Point(1, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 3))

    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECRESET(esccmd.ReverseWraparound)
    esccmd.CUP(Point(1, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 3))

  def test_BS_ReverseWrapWithLeftRight(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(10, 2))

  def test_BS_ReversewrapFromLeftEdgeToRightMargin(self):
    """If cursor starts at left edge of screen, left of left margin, backspace
    takes it to the right margin."""
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(1, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(10, 2))

  @knownBug(terminal="xterm",
            reason="BS wraps past top margin. Bad idea in my opinion, but there is no standard for reverse wrap.")
  def test_BS_ReverseWrapWontPassTop(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSTBM(2, 5)
    esccmd.CUP(Point(1, 2))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 2))

  def test_BS_StopsAtLeftMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 1))
    escio.Write(esc.BS)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  def test_BS_MovesLeftWhenLeftOfLeftMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(4, 1))
    escio.Write(esc.BS)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(3, 1))

  def test_BS_StopsAtOrigin(self):
    esccmd.CUP(Point(1, 1))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 1))

  def test_BS_CursorStartsInDoWrapPosition(self):
    """Cursor is right of right edge of screen."""
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("ab")
    escio.Write(esc.BS)
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1),
                                 [ "Xb" ])

