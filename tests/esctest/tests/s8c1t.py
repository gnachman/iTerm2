from esc import FF, NUL, S7C1T, S8C1T, blank
import escargs
import esccmd
import escio
from escutil import AssertEQ, AssertScreenCharsInRectEqual, GetCursorPosition, GetScreenSize, knownBug, optionRequired
from esctypes import Point, Rect

# Most C1 codes have their own tests for 8-bit controls and are not duplicated here.

class S8C1TTests(object):
  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_S8C1T_CSI(self):
    escio.use8BitControls = True
    escio.Write(S8C1T)
    esccmd.CUP(Point(1, 2))
    escio.Write(S7C1T)
    escio.use8BitControls = False
    AssertEQ(GetCursorPosition(), Point(1, 2))

  @knownBug(terminal="iTerm2", reason="8-bit controls not implemented.")
  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_S8C1T_DCS(self):
    esccmd.DECSTBM(5, 6)
    escio.use8BitControls = True
    escio.Write(S8C1T)
    esccmd.DECRQSS("r")
    result = escio.ReadDCS()
    escio.Write(S7C1T)
    escio.use8BitControls = False
    AssertEQ(result, "1$r5;6r")

  @knownBug(terminal="iTerm2",
            reason="Protection not implemented.")
  @optionRequired(terminal="xterm", option=escargs.DISABLE_WIDE_CHARS)
  def test_S8C1T_SPA_EPA(self):
    """There is no test for SPA and EPA (it's in the erasure tests, like
    DECSED) so the test for 8 bit controls goes here."""
    escio.use8BitControls = True
    escio.Write(S8C1T)

    escio.Write("a")
    escio.Write("b")
    esccmd.SPA()
    escio.Write("c")
    esccmd.EPA()

    escio.Write(S7C1T)
    escio.use8BitControls = False

    esccmd.CUP(Point(1, 1))
    esccmd.ECH(3)
    AssertScreenCharsInRectEqual(Rect(1, 1, 3, 1),
                                 [ blank() * 2 + "c" ])


