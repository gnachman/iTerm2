import base64
from esc import NUL
import escargs
import esccmd
import escio
from escutil import AssertEQ, knownBug, optionRequired
from esctypes import Rect

class ResetColorTests(object):
  @knownBug(terminal="iTerm2", reason="Query not implemented.")
  def test_ResetColor_Standard(self):
    n = "0"
    esccmd.ChangeColor(n, "?")
    original = escio.ReadOSC("4")

    esccmd.ChangeColor(n, "#aaaabbbbcccc")
    esccmd.ChangeColor(n, "?")
    AssertEQ(escio.ReadOSC("4"), ";" + n + ";rgb:aaaa/bbbb/cccc")

    esccmd.ResetColor(n)
    esccmd.ChangeColor(n, "?")
    AssertEQ(escio.ReadOSC("4"), original)

  @knownBug(terminal="iTerm2", reason="Query not implemented.")
  def test_ResetColor_All(self):
    esccmd.ChangeColor("3", "?")
    original = escio.ReadOSC("4")

    esccmd.ChangeColor("3", "#aabbcc")
    esccmd.ChangeColor("3", "?")
    AssertEQ(escio.ReadOSC("4"), ";3;rgb:aaaa/bbbb/cccc")

    esccmd.ResetColor()
    esccmd.ChangeColor("3", "?")
    AssertEQ(escio.ReadOSC("4"), original)

