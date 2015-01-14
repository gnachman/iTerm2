from esc import NUL, LF, VT, FF
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class SMTests(object):
  def test_SM_IRM(self):
    """Turn on insert mode."""
    escio.Write("abc")
    esccmd.CUP(Point(1, 1))
    esccmd.SM(esccmd.IRM)
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "Xabc" ])

  def test_SM_IRM_DoesNotWrapUnlessCursorAtMargin(self):
    """Insert mode does not cause wrapping."""
    size = GetScreenSize()
    escio.Write("a" * (size.width() - 1))
    escio.Write("b")
    esccmd.CUP(Point(1, 1))
    esccmd.SM(esccmd.IRM)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    esccmd.CUP(Point(size.width(), 1))
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "Z" ])

  def test_SM_IRM_TruncatesAtRightMargin(self):
    """When a left-right margin is set, insert truncates the line at the right margin."""
    esccmd.CUP(Point(5, 1))

    escio.Write("abcdef")

    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 10)

    esccmd.CUP(Point(7, 1))
    esccmd.SM(esccmd.IRM)
    escio.Write("X")
    esccmd.DECRESET(esccmd.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(5, 1, 11, 1), [ "abXcde" + NUL ])

  def doLinefeedModeTest(self, code):
    esccmd.RM(esccmd.LNM)
    esccmd.CUP(Point(5, 1))
    escio.Write(code)
    AssertEQ(GetCursorPosition(), Point(5, 2))

    esccmd.SM(esccmd.LNM)
    esccmd.CUP(Point(5, 1))
    escio.Write(code)
    AssertEQ(GetCursorPosition(), Point(1, 2))

  @knownBug(terminal="iTerm2", reason="LNN not implemented.")
  def test_SM_LNM(self):
    """In linefeed mode LF, VT, and FF perform a carriage return after doing
    an index. Also any report with a CR gets a CR LF instead, but I'm not sure
    when that would happen."""
    self.doLinefeedModeTest(LF)
    self.doLinefeedModeTest(VT)
    self.doLinefeedModeTest(FF)
