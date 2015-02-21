from esc import NUL
import esccmd
import escio
from esclog import LogInfo
from escutil import AssertEQ, AssertTrue, knownBug
from esctypes import Rect

class ChangeSpecialColorTests(object):
  """Color reporting isn't officially documented for special colors but works
  well enough for the test. It responds with mode 4 and a color index 16 or 256
  higher than what was queried."""

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_Multiple(self):
    """OSC 4 ; c1 ; spec1 ; s2 ; spec2 ; ST"""
    esccmd.ChangeSpecialColor("0",
                              "rgb:f0f0/f0f0/f0f0",
                              "1",
                              "rgb:f0f0/0000/0000")
    esccmd.ChangeSpecialColor("0", "?", "1", "?")
    AssertTrue(escio.ReadOSC("4") in [";16;rgb:f0f0/f0f0/f0f0",
                                      ";256;rgb:f0f0/f0f0/f0f0"])
    AssertTrue(escio.ReadOSC("4") in [";17;rgb:f0f0/0000/0000",
                                      ";257;rgb:f0f0/0000/0000"])

    esccmd.ChangeSpecialColor("0",
                              "rgb:8080/8080/8080",
                              "1",
                              "rgb:8080/0000/0000")
    esccmd.ChangeSpecialColor("0", "?", "1", "?")
    AssertTrue(escio.ReadOSC("4") in [";16;rgb:8080/8080/8080", ";256;rgb:8080/8080/8080"])
    s = escio.ReadOSC("4")
    LogInfo("Read: " + s)
    AssertTrue(s in [";17;rgb:8080/0000/0000", ";257;rgb:8080/0000/0000"])

  def doChangeSpecialColorTest(self, c, value, rgb):
    esccmd.ChangeSpecialColor(c, value)
    esccmd.ChangeSpecialColor(c, "?")
    s = escio.ReadOSC("4")
    AssertTrue(s in [ ";" + str(int(c) + 16) + ";rgb:" + rgb,
                      ";" + str(int(c) + 256) + ";rgb:" + rgb ])

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_RGB(self):
    self.doChangeSpecialColorTest("0", "rgb:f0f0/f0f0/f0f0", "f0f0/f0f0/f0f0")
    self.doChangeSpecialColorTest("0", "rgb:8080/8080/8080", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_Hash3(self):
    self.doChangeSpecialColorTest("0", "#fff", "f0f0/f0f0/f0f0")
    self.doChangeSpecialColorTest("0", "#888", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_Hash6(self):
    self.doChangeSpecialColorTest("0", "#f0f0f0", "f0f0/f0f0/f0f0")
    self.doChangeSpecialColorTest("0", "#808080", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_Hash9(self):
    self.doChangeSpecialColorTest("0", "#f00f00f00", "f0f0/f0f0/f0f0")
    self.doChangeSpecialColorTest("0", "#800800800", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_Hash12(self):
    self.doChangeSpecialColorTest("0", "#f000f000f000", "f0f0/f0f0/f0f0")
    self.doChangeSpecialColorTest("0", "#800080008000", "8080/8080/8080")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_RGBI(self):
    self.doChangeSpecialColorTest("0", "rgbi:1/1/1", "ffff/ffff/ffff")
    self.doChangeSpecialColorTest("0", "rgbi:0.5/0.5/0.5", "c1c1/bbbb/bbbb")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_CIEXYZ(self):
    self.doChangeSpecialColorTest("0", "CIEXYZ:1/1/1", "ffff/ffff/ffff")
    self.doChangeSpecialColorTest("0", "CIEXYZ:0.5/0.5/0.5", "dddd/b5b5/a0a0")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_CIEuvY(self):
    self.doChangeSpecialColorTest("0", "CIEuvY:1/1/1", "ffff/ffff/ffff")
    self.doChangeSpecialColorTest("0", "CIEuvY:0.5/0.5/0.5", "ffff/a3a3/aeae")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_CIExyY(self):
    self.doChangeSpecialColorTest("0", "CIExyY:1/1/1", "ffff/ffff/ffff")
    self.doChangeSpecialColorTest("0", "CIExyY:0.5/0.5/0.5", "f7f7/b3b3/0e0e")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_CIELab(self):
    self.doChangeSpecialColorTest("0", "CIELab:1/1/1", "6c6c/6767/6767")
    self.doChangeSpecialColorTest("0", "CIELab:0.5/0.5/0.5", "5252/4f4f/4f4f")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_CIELuv(self):
    self.doChangeSpecialColorTest("0", "CIELuv:1/1/1", "1616/1414/0e0e")
    self.doChangeSpecialColorTest("0", "CIELuv:0.5/0.5/0.5", "0e0e/1313/0e0e")

  @knownBug(terminal="iTerm2", reason="Color reporting not implemented.", shouldTry=False)
  def test_ChangeSpecialColor_TekHVC(self):
    self.doChangeSpecialColorTest("0", "TekHVC:1/1/1", "1a1a/1313/0f0f")
    self.doChangeSpecialColorTest("0", "TekHVC:0.5/0.5/0.5", "1111/1313/0e0e")


