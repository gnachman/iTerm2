import base64
import escargs
import esccmd
import escio
from escutil import AssertEQ, knownBug, optionRequired

class ManipulateSelectionDataTests(object):
  """No tests for buffers besides default; they're so x-specific that they're
  not worth testing for my purposes."""
  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED)
  @knownBug(terminal="iTerm2", reason="'OSC 52 ; ?' (query) not supported")
  def test_ManipulateSelectionData_default(self):
    s = "testing 123"
    esccmd.ManipulateSelectionData(Pd=base64.b64encode(s))
    esccmd.ManipulateSelectionData(Pd="?")
    r = escio.ReadOSC("52")
    AssertEQ(r, ";s0;" + base64.b64encode(s))

