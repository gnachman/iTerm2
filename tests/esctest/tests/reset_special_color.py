import base64
from esc import NUL
import escargs
import esccmd
import escio
from escutil import AssertEQ, knownBug, optionRequired
from esctypes import Rect

class ResetSpecialColorTests(object):
  @knownBug(terminal="iTerm2", reason="Query not implemented.")
  def test_ResetSpecialColor_Single(self):
    n = "0"
    esccmd.ChangeSpecialColor(n, "?")
    original = escio.ReadOSC("4")

    esccmd.ChangeSpecialColor(n, "#aaaabbbbcccc")
    esccmd.ChangeSpecialColor(n, "?")
    AssertEQ(escio.ReadOSC("4"), ";" + str(int(n) + 16) + ";rgb:aaaa/bbbb/cccc")

    esccmd.ResetSpecialColor(n)
    esccmd.ChangeSpecialColor(n, "?")
    AssertEQ(escio.ReadOSC("4"), original)

  @knownBug(terminal="iTerm2", reason="Query not implemented.")
  def test_ResetSpecialColor_Multiple(self):
    n1 = "0"
    n2 = "1"
    esccmd.ChangeSpecialColor(n1, "?", n2, "?")
    original1 = escio.ReadOSC("4")
    original2 = escio.ReadOSC("4")

    esccmd.ChangeSpecialColor(n1, "#aaaabbbbcccc")
    esccmd.ChangeSpecialColor(n2, "#ddddeeeeffff")
    esccmd.ChangeSpecialColor(n1, "?")
    AssertEQ(escio.ReadOSC("4"), ";" + str(int(n1) + 16) + ";rgb:aaaa/bbbb/cccc")
    esccmd.ChangeSpecialColor(n2, "?")
    AssertEQ(escio.ReadOSC("4"), ";" + str(int(n2) + 16) + ";rgb:dddd/eeee/ffff")

    esccmd.ResetSpecialColor(n1, n2)
    esccmd.ChangeSpecialColor(n1, "?", n2, "?")
    actual1 = escio.ReadOSC("4")
    actual2 = escio.ReadOSC("4")
    AssertEQ(actual1, original1)
    AssertEQ(actual2, original2)

  @knownBug(terminal="iTerm2", reason="Query not implemented.")
  def test_ResetSpecialColor_Dynamic(self):
    esccmd.ChangeSpecialColor("10", "?")
    original = escio.ReadOSC("10")

    esccmd.ChangeSpecialColor("10", "#aaaabbbbcccc")
    esccmd.ChangeSpecialColor("10", "?")
    AssertEQ(escio.ReadOSC("10"), ";rgb:aaaa/bbbb/cccc")

    esccmd.ResetDynamicColor("110")
    esccmd.ChangeSpecialColor("10", "?")
    AssertEQ(escio.ReadOSC("10"), original)

