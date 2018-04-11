import esc
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, vtLevel
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

  @vtLevel(4)
  def test_BS_ReverseWrapWithLeftRight(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(10, 2))

  @vtLevel(4)
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

  @inclusiveVariant(terminals=["xterm"],
	            reason="xterm chooses to wrap to the bottom. There is no spec for reverse wrap.")
  def test_BS_ReverseWrapWontPassTop(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSTBM(2, 5)
    esccmd.CUP(Point(1, 2))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(80, 5))

  @exclusiveVariant(terminals=["xterm"],
	            reason="In this default variant of the test, reverse wrap at the top does not move the cursor. There is no spec for reverse wrap.")
  def test_BS_ReverseWrapWontPassTop(self):
    esccmd.DECSET(esccmd.DECAWM)
    esccmd.DECSET(esccmd.ReverseWraparound)
    esccmd.DECSTBM(2, 5)
    esccmd.CUP(Point(1, 2))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 2))

  @vtLevel(4)
  def test_BS_StopsAtLeftMargin(self):
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)
    esccmd.CUP(Point(5, 1))
    escio.Write(esc.BS)
    esccmd.DECRESET(esccmd.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  @vtLevel(4)
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

  @vtLevel(4)
  def test_BS_CursorStartsInDoWrapPosition(self):
    """Cursor is right of right edge of screen."""
    size = GetScreenSize()
    esccmd.CUP(Point(size.width() - 1, 1))
    escio.Write("ab")
    escio.Write(esc.BS)
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(size.width() - 1, 1, size.width(), 1),
                                 [ "Xb" ])

