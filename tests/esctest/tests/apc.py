from esc import NUL, ST, S7C1T, S8C1T
import escargs
import esccmd
import escio
from escutil import AssertScreenCharsInRectEqual, knownBug, optionRequired
from esctypes import Rect

class APCTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_APC_Basic(self):
    esccmd.APC()
    escio.Write("xyz")
    escio.Write(ST)
    escio.Write("A")

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ "A" + NUL * 2 ])

  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_APC_8bit(self):
    escio.use8BitControls = True
    escio.Write(S8C1T)

    esccmd.APC()
    escio.Write("xyz")
    escio.Write(ST)
    escio.Write("A")

    escio.Write(S7C1T)
    escio.use8BitControls = False

    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ "A" + NUL * 2 ])

