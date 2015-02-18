from esc import NUL
import escargs
import esccsi
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetIconTitle, GetScreenSize, GetWindowTitle, knownBug, optionRequired

SET_HEX = 0
QUERY_HEX = 1
SET_UTF8 = 2
QUERY_UTF8 = 3

class SMTitleTests(object):
  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetHexQueryUTF8(self):
    esccsi.RM_Title(SET_UTF8, QUERY_HEX)
    esccsi.SM_Title(SET_HEX, QUERY_UTF8)

    esccsi.ChangeWindowTitle("6162")
    AssertEQ(GetWindowTitle(), "ab")
    esccsi.ChangeWindowTitle("61")
    AssertEQ(GetWindowTitle(), "a")

    esccsi.ChangeIconTitle("6162")
    AssertEQ(GetIconTitle(), "ab")
    esccsi.ChangeIconTitle("61")
    AssertEQ(GetIconTitle(), "a")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryUTF8(self):
    esccsi.RM_Title(SET_HEX, QUERY_HEX)
    esccsi.SM_Title(SET_UTF8, QUERY_UTF8)

    esccsi.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "ab")
    esccsi.ChangeWindowTitle("a")
    AssertEQ(GetWindowTitle(), "a")

    esccsi.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "ab")
    esccsi.ChangeIconTitle("a")
    AssertEQ(GetIconTitle(), "a")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryHex(self):
    esccsi.RM_Title(SET_HEX, QUERY_UTF8)
    esccsi.SM_Title(SET_UTF8, QUERY_HEX)

    esccsi.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "6162")
    esccsi.ChangeWindowTitle("a")
    AssertEQ(GetWindowTitle(), "61")

    esccsi.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "6162")
    esccsi.ChangeIconTitle("a")
    AssertEQ(GetIconTitle(), "61")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetHexQueryHex(self):
    esccsi.RM_Title(SET_UTF8, QUERY_UTF8)
    esccsi.SM_Title(SET_HEX, QUERY_HEX)

    esccsi.ChangeWindowTitle("6162")
    AssertEQ(GetWindowTitle(), "6162")
    esccsi.ChangeWindowTitle("61")
    AssertEQ(GetWindowTitle(), "61")

    esccsi.ChangeIconTitle("6162")
    AssertEQ(GetIconTitle(), "6162")
    esccsi.ChangeIconTitle("61")
    AssertEQ(GetIconTitle(), "61")

