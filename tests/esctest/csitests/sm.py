from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class SMTests(object):
  def test_SM_IRM(self):
    """Turn on insert mode."""
    escio.Write("abc")
    esccsi.CUP(Point(1, 1))
    esccsi.SM(esccsi.IRM)
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "Xabc" ])

  def test_SM_IRM_DoesNotWrapUnlessCursorAtMargin(self):
    """Insert mode does not cause wrapping."""
    size = GetScreenSize()
    escio.Write("a" * (size.width() - 1))
    escio.Write("b")
    esccsi.CUP(Point(1, 1))
    esccsi.SM(esccsi.IRM)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    esccsi.CUP(Point(size.width(), 1))
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "Z" ])

  def test_SM_IRM_TruncatesAtRightMargin(self):
    """When a left-right margin is set, insert truncates the line at the right margin."""
    esccsi.CUP(Point(5, 1))

    escio.Write("abcdef")

    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 10)

    esccsi.CUP(Point(7, 1))
    esccsi.SM(esccsi.IRM)
    escio.Write("X")
    esccsi.DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(5, 1, 11, 1), [ "abXcde" + NUL ])

