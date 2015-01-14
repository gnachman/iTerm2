from esc import FF, NUL, blank
import escargs
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, optionRequired, vtLevel
from esctypes import Point, Rect

class DECRQSSTests(object):
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECRQSS_DECSCA(self):
    esccmd.DECSCA(1)
    esccmd.DECRQSS('"q')
    result = escio.ReadDCS()
    AssertEQ(result, '1$r1"q')

  @vtLevel(2)
  @knownBug(terminal="xterm", reason="DECSCL incorrectly always sets 8 bit controls")
  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECRQSS_DECSCL(self):
    esccmd.DECSCL(65, 1)
    esccmd.DECRQSS('"p')
    result = escio.ReadDCS()
    AssertEQ(result, '1$r65;1"p')

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECRQSS_DECSTBM(self):
    esccmd.DECSTBM(5, 6)
    esccmd.DECRQSS("r")
    result = escio.ReadDCS()
    AssertEQ(result, "1$r5;6r")

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  def test_DECRQSS_SGR(self):
    esccmd.SGR(1)
    esccmd.DECRQSS("m")
    result = escio.ReadDCS()
    AssertEQ(result, "1$r0;1m")

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @knownBug(terminal="xterm", reason="DECRQSS always misreports DECSCUSR")
  def test_DECRQSS_DECSCUSR(self):
    esccmd.DECSCUSR(4)
    esccmd.DECRQSS(" q")
    result = escio.ReadDCS()
    AssertEQ(result, "1$r4 q")

  @knownBug(terminal="iTerm2", reason="Not implemented.")
  @vtLevel(4)
  def test_DECRQSS_DECSLRM(self):
    """Note: not in xcode docs, but supported."""
    esccmd.DECSET(esccmd.DECLRMM)
    esccmd.DECSLRM(3, 4)
    esccmd.DECRQSS("s")
    result = escio.ReadDCS()
    AssertEQ(result, "1$r3;4s")
