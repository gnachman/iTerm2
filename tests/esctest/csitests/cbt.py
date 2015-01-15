import esccsi
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug

class CBTTests(object):
  def __init__(self, args):
    self._args = args

  def test_CBT_OneTabStopByDefault(self):
    esccsi.CSI_CUP(Point(17, 1))
    esccsi.CSI_CBT()
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_ExplicitParameter(self):
    esccsi.CSI_CUP(Point(25, 1))
    esccsi.CSI_CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_StopsAtLeftEdge(self):
    esccsi.CSI_CUP(Point(25, 2))
    esccsi.CSI_CBT(5)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 2)

  def test_CBT_IgnoresRegion(self):
    # Set a scroll region.
    esccsi.CSI_DECSET(esccsi.DECLRMM)
    esccsi.CSI_DECSLRM(5, 30)

    # Move to center of region
    esccsi.CSI_CUP(Point(7, 9))

    # Tab backwards out of the region.
    esccsi.CSI_CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
