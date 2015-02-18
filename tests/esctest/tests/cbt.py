import esccmd
from esctypes import Point
from escutil import AssertEQ, GetCursorPosition, knownBug

class CBTTests(object):
  def test_CBT_OneTabStopByDefault(self):
    esccmd.CUP(Point(17, 1))
    esccmd.CBT()
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_ExplicitParameter(self):
    esccmd.CUP(Point(25, 1))
    esccmd.CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 9)

  def test_CBT_StopsAtLeftEdge(self):
    esccmd.CUP(Point(25, 2))
    esccmd.CBT(5)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
    AssertEQ(position.y(), 2)

  def test_CBT_IgnoresRegion(self):
    # Set a scroll region.
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(5, 30)

    # Move to center of region
    esccmd.CUP(Point(7, 9))

    # Tab backwards out of the region.
    esccmd.CBT(2)
    position = GetCursorPosition()
    AssertEQ(position.x(), 1)
