from esc import TAB, S8C1T, S7C1T
import escargs
import esccmd
import escio
from escutil import AssertEQ, GetCursorPosition, knownBug, optionRequired
from esctypes import Point

class HTSTests(object):
  def test_HTS_Basic(self):
    # Remove tabs
    esccmd.TBC(3)

    # Set a tabstop at 20
    esccmd.CUP(Point(20, 1))
    esccmd.HTS()

    # Move to 1 and then tab to 20
    esccmd.CUP(Point(1, 1))
    escio.Write(TAB)

    AssertEQ(GetCursorPosition().x(), 20)

  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  def test_HTS_8bit(self):
    # Remove tabs
    esccmd.TBC(3)

    # Set a tabstop at 20
    esccmd.CUP(Point(20, 1))

    # Do 8 bit hts
    escio.use8BitControls = True
    escio.Write(S8C1T)
    esccmd.HTS()
    escio.Write(S7C1T)
    escio.use8BitControls = False

    # Move to 1 and then tab to 20
    esccmd.CUP(Point(1, 1))
    escio.Write(TAB)

    AssertEQ(GetCursorPosition().x(), 20)
