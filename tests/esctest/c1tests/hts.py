from esc import TAB
import escc1
import esccsi
import escio
from escutil import AssertEQ, GetCursorPosition
from esctypes import Point

class HTSTests(object):
  def test_HTS_Basic(self):
    # Remove tabs
    esccsi.TBC(3)

    # Set a tabstop at 20
    esccsi.CUP(Point(20, 1))
    escc1.HTS()

    # Move to 1 and then tab to 20
    esccsi.CUP(Point(1, 1))
    escio.Write(TAB)

    AssertEQ(GetCursorPosition().x(), 20)
