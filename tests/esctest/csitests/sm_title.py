from esc import NUL
import esccsi
import escio
import escosc
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, GetWindowTitle, knownBug

SET_HEX = 0
QUERY_HEX = 1
SET_UTF8 = 2
QUERY_UTF8 = 3

class SMTitleTests(object):
  def __init__(self, args):
    self._args = args

  @knownBug(terminal="xterm", reason="Title reporting disabled by default.")
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetHexQueryUTF8(self):
    esccsi.CSI_SM_Title(SET_HEX, QUERY_UTF8)

    escosc.ChangeWindowTitle("6162")
    AssertEQ(GetWindowTitle(), "ab")
    escosc.ChangeWindowTitle("")
    AssertEQ(GetWindowTitle(), "")

    escosc.ChangeIconTitle("6162")
    AssertEQ(GetIconTitle(), "ab")
    escosc.ChangeIconTitle("")
    AssertEQ(GetIconTitle(), "")

  @knownBug(terminal="xterm", reason="Title reporting disabled by default.")
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryUTF8(self):
    esccsi.CSI_SM_Title(SET_UTF8, QUERY_UTF8)

    escosc.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "ab")
    escosc.ChangeWindowTitle("")
    AssertEQ(GetWindowTitle(), "")

    escosc.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "ab")
    escosc.ChangeIconTitle("")
    AssertEQ(GetIconTitle(), "")

  @knownBug(terminal="xterm", reason="Title reporting disabled by default.")
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryHex(self):
    esccsi.CSI_SM_Title(SET_UTF8, QUERY_HEX)

    escosc.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "6162")
    escosc.ChangeWindowTitle("")
    AssertEQ(GetWindowTitle(), "")

    escosc.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "6162")
    escosc.ChangeIconTitle("")
    AssertEQ(GetIconTitle(), "")

