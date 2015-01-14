from esc import NUL
import escargs
import esccmd
from esccmd import SET_HEX, QUERY_HEX, SET_UTF8, QUERY_UTF8
import escio
from esctypes import Point, Rect
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetIconTitle, GetScreenSize, GetWindowTitle, knownBug, optionRequired


class SMTitleTests(object):
  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetHexQueryUTF8(self):
    esccmd.RM_Title(SET_UTF8, QUERY_HEX)
    esccmd.SM_Title(SET_HEX, QUERY_UTF8)

    esccmd.ChangeWindowTitle("6162")
    AssertEQ(GetWindowTitle(), "ab")
    esccmd.ChangeWindowTitle("61")
    AssertEQ(GetWindowTitle(), "a")

    esccmd.ChangeIconTitle("6162")
    AssertEQ(GetIconTitle(), "ab")
    esccmd.ChangeIconTitle("61")
    AssertEQ(GetIconTitle(), "a")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryUTF8(self):
    esccmd.RM_Title(SET_HEX, QUERY_HEX)
    esccmd.SM_Title(SET_UTF8, QUERY_UTF8)

    esccmd.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "ab")
    esccmd.ChangeWindowTitle("a")
    AssertEQ(GetWindowTitle(), "a")

    esccmd.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "ab")
    esccmd.ChangeIconTitle("a")
    AssertEQ(GetIconTitle(), "a")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetUTF8QueryHex(self):
    esccmd.RM_Title(SET_HEX, QUERY_UTF8)
    esccmd.SM_Title(SET_UTF8, QUERY_HEX)

    esccmd.ChangeWindowTitle("ab")
    AssertEQ(GetWindowTitle(), "6162")
    esccmd.ChangeWindowTitle("a")
    AssertEQ(GetWindowTitle(), "61")

    esccmd.ChangeIconTitle("ab")
    AssertEQ(GetIconTitle(), "6162")
    esccmd.ChangeIconTitle("a")
    AssertEQ(GetIconTitle(), "61")

  @optionRequired(terminal="xterm", option=escargs.XTERM_WINOPS_ENABLED,
      allowPassWithoutOption=True)
  @knownBug(terminal="iTerm2", reason="SM_Title not implemented.")
  def test_SMTitle_SetHexQueryHex(self):
    esccmd.RM_Title(SET_UTF8, QUERY_UTF8)
    esccmd.SM_Title(SET_HEX, QUERY_HEX)

    esccmd.ChangeWindowTitle("6162")
    AssertEQ(GetWindowTitle(), "6162")
    esccmd.ChangeWindowTitle("61")
    AssertEQ(GetWindowTitle(), "61")

    esccmd.ChangeIconTitle("6162")
    AssertEQ(GetIconTitle(), "6162")
    esccmd.ChangeIconTitle("61")
    AssertEQ(GetIconTitle(), "61")

