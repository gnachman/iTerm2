from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class SMTests(object):
  def __init__(self, args):
    self._args = args

  def test_SM_IRM(self):
    """Turn on insert mode."""
    escio.Write("abc")
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_SM(esccsi.IRM)
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 1, 4, 1), [ "Xabc" ])

  def test_SM_IRM_DoesNotWrapUnlessCursorAtMargin(self):
    """Insert mode does not cause wrapping."""
    size = GetScreenSize()
    escio.Write("a" * (size.width() - 1))
    escio.Write("b")
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_SM(esccsi.IRM)
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    escio.Write("X")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ NUL ])
    esccsi.CSI_CUP(Point(size.width(), 1))
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 2, 1, 2), [ "Z" ])

  def test_SM_IRM_TruncatesAtRightMargin(self):
    """When a left-right margin is set, insert truncates the line at the right margin."""
    esccsi.CSI_CUP(Point(5, 1))

    escio.Write("abcdef")

    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 10)

    esccsi.CSI_CUP(Point(7, 1))
    esccsi.CSI_SM(esccsi.IRM)
    escio.Write("X")
    esccsi.CSI_DECRESET(esccsi.DECLRMM)

    AssertScreenCharsInRectEqual(Rect(5, 1, 11, 1), [ "abXcde" + NUL ])

