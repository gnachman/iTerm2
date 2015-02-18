from esc import NUL
import esccmd
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class RMTests(object):
  def test_RM_IRM(self):
    # First turn on insert mode
    esccmd.SM(esccmd.IRM)
    esccmd.CUP(Point(1, 1))
    escio.Write("X")
    esccmd.CUP(Point(1, 1))
    escio.Write("W")

    # Now turn on replace mode
    esccmd.CUP(Point(1, 1))
    esccmd.RM(esccmd.IRM)
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 1, 2, 1), [ "YZ" ])

