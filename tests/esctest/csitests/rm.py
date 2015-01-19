from esc import NUL
import esccsi
import escio
from escutil import AssertScreenCharsInRectEqual, GetScreenSize
from esctypes import Point, Rect

# AM, SRM, and LNM should also be supported but are not currently testable
# because they require user interaction.
class RMTests(object):
  def __init__(self, args):
    self._args = args

  def test_RM_IRM(self):
    # First turn on insert mode
    esccsi.CSI_SM(esccsi.IRM)
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("X")
    esccsi.CSI_CUP(Point(1, 1))
    escio.Write("W")

    # Now turn on replace mode
    esccsi.CSI_CUP(Point(1, 1))
    esccsi.CSI_RM(esccsi.IRM)
    escio.Write("YZ")
    AssertScreenCharsInRectEqual(Rect(1, 1, 2, 1), [ "YZ" ])

