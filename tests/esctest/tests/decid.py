from esc import NUL, ST, S8C1T, S7C1T
import escargs
import esccmd
import escio
from escutil import AssertTrue, knownBug, optionRequired

class DECIDTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented.", shouldTry=False)
  def test_DECID_Basic(self):
    esccmd.DECID()
    params = escio.ReadCSI("c", expected_prefix="?")
    AssertTrue(len(params) > 0)

  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  def test_DECID_8bit(self):
    escio.use8BitControls = True
    escio.Write(S8C1T)

    esccmd.DECID()
    params = escio.ReadCSI("c", expected_prefix="?")
    AssertTrue(len(params) > 0)

    escio.Write(S7C1T)
    escio.use8BitControls = False
