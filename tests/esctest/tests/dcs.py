from esc import NUL
import escio
from escutil import AssertScreenCharsInRectEqual, knownBug, vtLevel
from esctypes import Rect

class DCSTests(object):
  @vtLevel(4)
  def test_DCS_Unrecognized(self):
    """An unrecognized DCS code should be swallowed"""
    escio.WriteDCS("z", "0")
    AssertScreenCharsInRectEqual(Rect(1, 1, 1, 1), NUL)

