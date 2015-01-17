import esccsi
import escio
from escutil import AssertEQ, AssertGE, knownBug

class DA2Tests(object):
  def __init__(self, args):
    self._args = args

  def handleDA2Response(self):
    params = escio.ReadCSI('c', expected_prefix='>')
    if self._args.expected_terminal == "xterm":
      AssertGE(params[0], 41)
      AssertGE(params[1], 314)
      AssertEQ(len(params), 2)
    elif self._args.expected_terminal == "iTerm2":
      AssertEQ(params[0], 0)
      AssertEQ(params[1], 95)
      AssertEQ(len(params), 2)

  @knownBug(terminal="iTerm2", reason="Extra empty parameter at end of response")
  def test_DA2_NoParameter(self):
    esccsi.CSI_DA2()
    self.handleDA2Response()

  @knownBug(terminal="iTerm2", reason="Extra empty parameter at end of response")
  def test_DA2_0(self):
    esccsi.CSI_DA2(0)
    self.handleDA2Response()




