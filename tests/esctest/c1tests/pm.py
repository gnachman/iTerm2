from esc import NUL, ST, S7C1T, S8C1T
import escargs
import escc1
import escio
from escutil import AssertScreenCharsInRectEqual, knownBug, optionRequired
from esctypes import Rect

class PMTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_PM_Basic(self):
    escc1.PM()
    escio.Write("xyz")
    escio.Write(ST)
    escio.Write("A")

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ "A" + NUL * 2 ])

  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  def test_PM_8bit(self):
    escio.use8BitControls = True
    escio.Write(S8C1T)
    escc1.PM()
    escio.Write("xyz")
    escio.Write(ST)
    escio.Write("A")
    escio.Write(S7C1T)
    escio.use8BitControls = False

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ "A" + NUL * 2 ])
