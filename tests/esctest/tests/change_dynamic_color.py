from esc import NUL
import esccmd
import escio
from escutil import AssertEQ, knownBug
from esctypes import Rect

class ChangeDynamicColorTests(object):
  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_Multiple(self):
    """OSC 4 ; c1 ; spec1 ; s2 ; spec2 ; ST"""
    esccmd.ChangeDynamicColor("10",
                              "rgb:f0f0/f0f0/f0f0",
                              "rgb:f0f0/0000/0000")
    esccmd.ChangeDynamicColor("10", "?", "?")
    AssertEQ(escio.ReadOSC("10"), ";rgb:f0f0/f0f0/f0f0")
    AssertEQ(escio.ReadOSC("11"), ";rgb:f0f0/0000/0000")

    esccmd.ChangeDynamicColor("10",
                              "rgb:8080/8080/8080",
                              "rgb:8080/0000/0000")
    esccmd.ChangeDynamicColor("10", "?", "?")
    AssertEQ(escio.ReadOSC("10"), ";rgb:8080/8080/8080")
    AssertEQ(escio.ReadOSC("11"), ";rgb:8080/0000/0000")

  def doChangeDynamicColorTest(self, c, value, rgb):
    esccmd.ChangeDynamicColor(c, value)
    esccmd.ChangeDynamicColor(c, "?")
    s = escio.ReadOSC(c)
    AssertEQ(s, ";rgb:" + rgb)

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_RGB(self):
    self.doChangeDynamicColorTest("10", "rgb:f0f0/f0f0/f0f0", "f0f0/f0f0/f0f0")
    self.doChangeDynamicColorTest("10", "rgb:8080/8080/8080", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_Hash3(self):
    self.doChangeDynamicColorTest("10", "#fff", "f0f0/f0f0/f0f0")
    self.doChangeDynamicColorTest("10", "#888", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_Hash6(self):
    self.doChangeDynamicColorTest("10", "#f0f0f0", "f0f0/f0f0/f0f0")
    self.doChangeDynamicColorTest("10", "#808080", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_Hash9(self):
    self.doChangeDynamicColorTest("10", "#f00f00f00", "f0f0/f0f0/f0f0")
    self.doChangeDynamicColorTest("10", "#800800800", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_Hash12(self):
    self.doChangeDynamicColorTest("10", "#f000f000f000", "f0f0/f0f0/f0f0")
    self.doChangeDynamicColorTest("10", "#800080008000", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_RGBI(self):
    self.doChangeDynamicColorTest("10", "rgbi:1/1/1", "ffff/ffff/ffff")
    self.doChangeDynamicColorTest("10", "rgbi:0.5/0.5/0.5", "c1c1/bbbb/bbbb")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_CIEXYZ(self):
    self.doChangeDynamicColorTest("10", "CIEXYZ:1/1/1", "ffff/ffff/ffff")
    self.doChangeDynamicColorTest("10", "CIEXYZ:0.5/0.5/0.5", "dddd/b5b5/a0a0")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_CIEuvY(self):
    self.doChangeDynamicColorTest("10", "CIEuvY:1/1/1", "ffff/ffff/ffff")
    self.doChangeDynamicColorTest("10", "CIEuvY:0.5/0.5/0.5", "ffff/a3a3/aeae")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_CIExyY(self):
    self.doChangeDynamicColorTest("10", "CIExyY:1/1/1", "ffff/ffff/ffff")
    self.doChangeDynamicColorTest("10", "CIExyY:0.5/0.5/0.5", "f7f7/b3b3/0e0e")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_CIELab(self):
    self.doChangeDynamicColorTest("10", "CIELab:1/1/1", "6c6c/6767/6767")
    self.doChangeDynamicColorTest("10", "CIELab:0.5/0.5/0.5", "5252/4f4f/4f4f")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_CIELuv(self):
    self.doChangeDynamicColorTest("10", "CIELuv:1/1/1", "1616/1414/0e0e")
    self.doChangeDynamicColorTest("10", "CIELuv:0.5/0.5/0.5", "0e0e/1313/0e0e")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeDynamicColor_TekHVC(self):
    self.doChangeDynamicColorTest("10", "TekHVC:1/1/1", "1a1a/1313/0f0f")
    self.doChangeDynamicColorTest("10", "TekHVC:0.5/0.5/0.5", "1111/1313/0e0e")


