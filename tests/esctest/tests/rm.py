from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class RMTests(object):
  def test_RM_IRM(self):
    # First turn on insert mode
    esccsi.SM(esccsi.IRM)
    esccsi.CUP(Point(1, 1))
    escio.Write("X")
    esccsi.CUP(Point(1, 1))
    escio.Write("W")

    # Now turn on replace mode
    esccsi.CUP(Point(1, 1))
    esccsi.RM(esccsi.IRM)
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 1, 2, 1), [ "YZ" ])

