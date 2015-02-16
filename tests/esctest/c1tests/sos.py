from esc import NUL, ST
import escc1
import escio
from escutil import AssertScreenCharsInRectEqual
from esctypes import Rect

class SOSTests(object):
  def test_SOS_Basic(self):
    escc1.SOS()
    escio.Write("xyz")
    escio.Write(ST)
    escio.Write("A")

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ "A" + NUL * 2 ])
