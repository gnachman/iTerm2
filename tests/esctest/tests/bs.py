import esc
import esccsi
import escio
from escutil import AssertEQ, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

class BSTests(object):
  def test_BS_Basic(self):
    esccsi.CUP(Point(3, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(2, 3))

  def test_BS_NoWrapByDefault(self):
    esccsi.CUP(Point(1, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 3))

  @knownBug(terminal="iTerm2",
            reason="Implementation differs from xterm, but maybe should match it. iTerm2 reverse wraps only if there is a soft EOL at the end of the preceding line.")
  def test_BS_WrapsInWraparoundMode(self):
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.CUP(Point(1, 3))
    escio.Write(esc.BS)
    size = GetScreenSize()
    AssertEQ(GetCursorPosition(), Point(size.width(), 2))

  @knownBug(terminal="iTerm2",
            reason="Implementation differs from xterm, but maybe should match it. iTerm2 never reverse-wraps with a left margin.")
  def test_BS_ReverseWrapWithLeftRight(self):
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.CUP(Point(5, 3))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(10, 2))

  def test_BS_StopsAtLeftMargin(self):
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.CUP(Point(5, 1))
    escio.Write(esc.BS)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(5, 1))

  @knownBug(terminal="iTerm2", reason="Doesn't move left.")
  def test_BS_MovesLeftWhenLeftOfLeftMargin(self):
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)
    esccsi.CUP(Point(4, 1))
    escio.Write(esc.BS)
    esccsi.DECRESET(esccsi.DECLRMM)
    AssertEQ(GetCursorPosition(), Point(3, 1))

  def test_BS_StopsAtOrigin(self):
    esccsi.CUP(Point(1, 1))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 1))

  @knownBug(terminal="xterm",
            reason="BS wraps past top margin. Bad idea in my opinion, but there is no standard for reverse wrap.")
  def test_BS_WillNotReverseWrapPastTopMargin(self):
    esccsi.DECSET(esccsi.DECAWM)
    esccsi.DECSET(esccsi.ReverseWraparound)
    esccsi.DECSTBM(2, 5)
    esccsi.CUP(Point(1, 2))
    escio.Write(esc.BS)
    AssertEQ(GetCursorPosition(), Point(1, 2))

