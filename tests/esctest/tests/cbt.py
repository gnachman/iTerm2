import esccsi
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug

class CBTTests(object):
  def test_CBT_OneTabStopByDefault(self):
    esccsi.CUP(Point(17, 1))
    esccsi.CBT()
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_ExplicitParameter(self):
    esccsi.CUP(Point(25, 1))
    esccsi.CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_StopsAtLeftEdge(self):
    esccsi.CUP(Point(25, 2))
    esccsi.CBT(5)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 2)

  def test_CBT_IgnoresRegion(self):
    # Set a scroll region.
    esccsi.DECSET(esccsi.DECLRMM)
    esccsi.DECSLRM(5, 30)

    # Move to center of region
    esccsi.CUP(Point(7, 9))

    # Tab backwards out of the region.
    esccsi.CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
